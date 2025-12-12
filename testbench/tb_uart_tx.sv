`timescale 1ns/1ps
`include "../design/uart_tx.v"

module tb_uart_tx;
    // ==============================================================================
    //  SECTION: Wire/Reg Declaration
    // ==============================================================================
    reg clk;      
    reg rst_n;    
    reg tx_tick;  
    
    // Configuration
    reg [1:0] i_num_bit_data; // 00:5, 01:6, 10:7, 11:8
    reg i_parity_en;
    reg i_parity_type;        // 0: Even, 1: Odd
    
    // Data & Control
    reg [7:0] i_data;
    reg i_tx_start;
    reg i_cts_n;              // 0: Clear to Send (OK), 1: Stop
    
    // Output
    wire o_tx_done;
    wire o_tx_serial;

    // parmeter for test
    parameter CLK_PERIOD = 20; // 50MHz

    // Baudrate simulation: 16 cycle clock = 1 tx_tick pulse
    localparam TICK_RATE = 16; 
    localparam BIT_TIME  = TICK_RATE * CLK_PERIOD; 

    // ==============================================================================
    //  SECTION: DUT Connection
    // ==============================================================================
    uart_tx inst_uart_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .tx_tick       (tx_tick),
        .i_num_bit_data(i_num_bit_data),
        .i_parity_en   (i_parity_en),
        .i_parity_type (i_parity_type),
        .i_data        (i_data),
        .i_tx_start    (i_tx_start),
        .i_cts_n       (i_cts_n),
        .o_tx_serial   (o_tx_serial),
        .o_tx_done     (o_tx_done)
    );

    // ==============================================================================
    //  SECTION: Clock & Baud Tick Generation
    // ==============================================================================
    // 1. Create Clock 50MHz
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // 2. Create tx_tick
    // 16 clock cycle -> enable tx_tick in 1 cycle
    reg [3:0] tick_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= 0;
            tx_tick  <= 0;
        end else begin
            if (tick_cnt == (TICK_RATE - 1)) begin
                tick_cnt <= 0;
                tx_tick  <= 1;
            end else begin
                tick_cnt <= tick_cnt + 1;
                tx_tick  <= 0;
            end
        end
    end

    // ==============================================================================
    //  SECTION: TASKS
    // ==============================================================================
    
    // Task send data
    task uart_drive_tx(input [7:0] data);
        begin
            @(posedge clk);
            i_data     <= data;
            i_tx_start <= 1;
            @(posedge clk);
            i_tx_start <= 0;
        end
    endtask

    // Task automatic check
    // Task will run parallel (fork-join) to watch o_tx_serial
    task uart_verify_serial_data(input [7:0] expected_data, input [1:0] num_bit, input parity_en, input parity_type);
        integer i;
        reg [7:0] received_data;
        reg       calc_p;
        integer   bit_limit;
        begin
            bit_limit = 5 + num_bit; // 00->5, 11->8
            received_data = 0;

            // 1. Wait Start Bit
            wait(o_tx_serial == 0);
            
            // 2. Jump to the middle of bit Start (0.5 * BIT_TIME)
            // simulation time, not clock cycle
            #(BIT_TIME / 2); 
            
            if (o_tx_serial !== 0) $display("[FAIL] Start bit unstable!");

            // 3. Jump to each bit to sample
            for (i = 0; i < bit_limit; i = i + 1) begin
                #(BIT_TIME); // jump 1 cycle
                received_data[i] = o_tx_serial;
            end

            // 4. Check Parity
            if (parity_en) begin
                #(BIT_TIME);
                // Calculate expected parity from received data
                case(num_bit)
                    2'b00: calc_p = ^received_data[4:0];
                    2'b01: calc_p = ^received_data[5:0];
                    2'b10: calc_p = ^received_data[6:0];
                    2'b11: calc_p = ^received_data[7:0];
                endcase
                if (parity_type) calc_p = ~calc_p; // Odd

                if (o_tx_serial !== calc_p) 
                    $error("[FAIL] Parity Mismatch! Exp: %b, Got: %b", calc_p, o_tx_serial);
                else 
                    $display("[INFO] Parity OK.");
            end

            // 5. Check Stop Bit
            #(BIT_TIME);
            if (o_tx_serial !== 1) 
                $error("[FAIL] Stop bit missing (Line not High)!");

            // 6. Compare Data
            // Mask bit (5 bit -> mask 3 high bit)
            case(num_bit)
                2'b00: received_data = received_data & 8'h1F;   
                2'b01: received_data = received_data & 8'h3F;
                2'b10: received_data = received_data & 8'h7F;
            endcase

            if (received_data === (expected_data & (8'hFF >> (8-bit_limit))))
                $display("[PASS] Data OK. Sent: 0x%h, Recv: 0x%h (Mode: %0d num_bit)", expected_data, received_data, bit_limit);
            else
                $error("[FAIL] Data Mismatch! Sent: 0x%h, Recv: 0x%h", expected_data, received_data);
        end
    endtask

    // ==============================================================================
    //  SECTION: STIMULUS
    // ==============================================================================
    initial begin
        // 1. Initial
        $display("================ UART TX TEST START ================");
        clk = 0;
        rst_n = 0;
        i_tx_start = 0;
        i_data = 0;
        i_cts_n = 0;
        
        // Default Config: 8N1
        i_num_bit_data = 2'b11; // 8 bit
        i_parity_en = 0;
        i_parity_type = 0;

        #100;
        rst_n = 1;
        #100;

        // ------------------------------------------------------------
        // CASE 1: 8N1 (8 Bit, No Parity) - Data 0x55
        // ------------------------------------------------------------
        $display("\n[CASE 1] Testing 8N1 with Data 0x55");
        fork
            begin
                uart_drive_tx(8'h55); // CPU send
                uart_verify_serial_data(8'h55, 2'b11, 0, 0);
            end
            begin
                wait(o_tx_done); 
            end
        join

        #200;

        // ------------------------------------------------------------
        // CASE 2: Test 5 bit Data (5N1) - Data 0x1F
        // ------------------------------------------------------------
        $display("\n[CASE 2] Testing 5N1 (Truncation check)");
        i_num_bit_data = 2'b00; // 5 bit mode
        fork
            begin
                uart_drive_tx(8'hFF); // send FF but expect 5 bit received (0x1F)
                uart_verify_serial_data(8'hFF, 2'b00, 0, 0);
            end
            begin
                wait(o_tx_done);
            end
        join
        
        #200;

        // ------------------------------------------------------------
        // CASE 3: Test Parity Even (8E1) - Data 0xAA
        // 0xAA (10101010) has 4 bit 1 -> Even Parity is 0
        // ------------------------------------------------------------
        $display("\n[CASE 3] Testing 8E1 (Even Parity)");
        i_num_bit_data = 2'b11; // 8 bit
        i_parity_en = 1;        // Enable Parity
        i_parity_type = 0;      // Even
        fork
            begin
                uart_drive_tx(8'hAA);
                uart_verify_serial_data(8'hAA, 2'b11, 1, 0);
            end
            begin
                wait(o_tx_done);
            end
        join
        
        #200;

        // ------------------------------------------------------------
        // CASE 4: Test Parity Odd (8O1) - Data 0xAA
        // 0xAA has 4 bit 1 -> Odd parity is 1
        // ------------------------------------------------------------
        $display("\n[CASE 4] Testing 8O1 (Odd Parity)");
        i_parity_type = 1; // Odd
        fork
            begin
                uart_drive_tx(8'hAA);
                uart_verify_serial_data(8'hAA, 2'b11, 1, 1);
            end
            begin
                wait(o_tx_done);
            end
        join
        
        #200;

        // ------------------------------------------------------------
        // CASE 5: Test Flow Control (CTS)
        // Pull CTS_N high (STOP), order to send, module must wait.
        // ------------------------------------------------------------
        $display("\n[CASE 5] Testing Flow Control (CTS Blocking)");
        i_parity_en = 0; // turn off parity
        
        i_cts_n = 1; // Peripheral is busy
        fork
            begin
                $display("   -> Asserting TX Start but CTS is HIGH (Busy)...");
                uart_drive_tx(8'h99);
            end
            // wait, o_tx_serial -> still 1 (IDLE), not done
            #1000;
            begin 
                 
                if (o_tx_serial == 0) $display("[FAIL] TX started while CTS was HIGH!");
                else                  $display("   -> TX held correctly.");
            end
            begin
                $display("   -> Releasing CTS (Active Low)...");
                i_cts_n = 0; // enable to send

                // Tx will run this time, check data for correctness
                uart_verify_serial_data(8'h99, 2'b11, 0, 0);
            end
            begin
                wait(o_tx_done);
            end
        join
        $display("[PASS] CTS Flow Control worked.");
        
        #500;
        $display("\n================ UART TX TEST DONE ================");
        $finish;
    end

    // gtkwave
    initial begin
        $dumpfile("uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end


endmodule