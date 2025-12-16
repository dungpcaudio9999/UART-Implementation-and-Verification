`timescale 1ns/1ps
`include "../design/uart_rx.v"

module tb_uart_rx;

    // =========================================================================
    // 1. TÍN HIỆU & THAM SỐ
    // =========================================================================
    reg clk;
    reg rst_n;
    reg rx_tick;
    reg [1:0] i_num_bit_data;
    reg i_parity_en;
    reg i_parity_type;
    reg i_rx_serial;
    wire [7:0] o_data;
    wire o_rx_done;
    wire o_parity_err;

    parameter DIVISOR = 325;
    parameter BIT_PERIOD = 104167; 

    // =========================================================================
    // 2. KẾT NỐI DUT & TẠO CLOCK
    // =========================================================================
    uart_rx dut (
        .clk(clk), .rst_n(rst_n), .rx_tick(rx_tick),
        .i_num_bit_data(i_num_bit_data),
        .i_parity_en(i_parity_en), .i_parity_type(i_parity_type),
        .i_rx_serial(i_rx_serial),
        .o_data(o_data), .o_rx_done(o_rx_done), .o_parity_err(o_parity_err)
    );

    initial clk = 0;
    always #10 clk = ~clk;

    reg [15:0] tick_counter;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tick_counter <= 0; rx_tick <= 0;
        end else begin
            if(tick_counter >= DIVISOR) begin
                tick_counter <= 0; rx_tick <= 1;
            end else begin
                tick_counter <= tick_counter + 1; rx_tick <= 0;
            end
        end
    end

    // =========================================================================
    // 3. TASK GỬI 1 BYTE (Dùng chung)
    // =========================================================================
    task send_byte(
        input [7:0] data, 
        input [1:0] width,
        input       p_en,
        input       p_type,
        input       inj_err,
        input [1:0] stop_bits
    );
        integer i, limit;
        reg calc_p;
        begin
            // Xác định số bit
            case(width)
                2'b00: limit = 5; 2'b01: limit = 6;
                2'b10: limit = 7; 2'b11: limit = 8;
            endcase

            // Tính Parity
            calc_p = 0;
            for(i=0; i<limit; i=i+1) calc_p = calc_p ^ data[i];
            if(p_type) calc_p = ~calc_p; 
            if(inj_err) calc_p = ~calc_p;

            // 1. Start Bit
            i_rx_serial = 0;
            #(BIT_PERIOD);
            
            // 2. Data Bits
            for(i=0; i<limit; i=i+1) begin
                i_rx_serial = data[i];
                #(BIT_PERIOD);
            end

            // 3. Parity Bit
            if(p_en) begin
                i_rx_serial = calc_p;
                #(BIT_PERIOD);
            end

            // 4. Stop Bit(s)
            i_rx_serial = 1;
            if(stop_bits == 2) #(BIT_PERIOD*2);
            else               #(BIT_PERIOD);
        end
    endtask

    // =========================================================================
    // 4. TASK: RUN STANDARD TEST (TC01 -> TC11, TC13)
    // =========================================================================
    task run_test(
        input [8*20:1] tc_name,    
        input [1:0]    width,      
        input          p_en,       
        input          p_type,     
        input [1:0]    stops,      
        input [7:0]    tx_data,    
        input          inj_err,    
        input          inj_glitch, 
        input [7:0]    exp_data,   
        input          exp_err     
    );
        begin
            i_num_bit_data = width;
            i_parity_en    = p_en;
            i_parity_type  = p_type;
            
            $display("---------------------------------------------------------------");
            $display("Running: %0s | Data: 0x%h | Parity Enable: %b | Parity Type: %b", tc_name, tx_data, p_en, p_type);

            fork
                // Thread A: Driver
                begin
                    if (inj_glitch) begin
                        i_rx_serial = 0; #(BIT_PERIOD/4); 
                        i_rx_serial = 1; #(BIT_PERIOD * 2); 
                    end else begin
                        send_byte(tx_data, width, p_en, p_type, inj_err, stops);
                    end
                end

                // Thread B: Monitor
                begin
                    if (inj_glitch) begin
                        #(BIT_PERIOD * 2);
                        if (o_rx_done == 0) $display("   [PASS] Glitch ignored.");
                        else                $display("   [FAIL] Glitch triggered RX_DONE!");
                    end else begin
                        wait(o_rx_done);
                        if(o_data === exp_data && o_parity_err === exp_err)
                            $display("   [PASS] Got: 0x%h | P_Err: %b", o_data, o_parity_err);
                        else
                            $display("   [FAIL] Got: 0x%h (Exp: 0x%h) | P_Err: %b", o_data, exp_data, o_parity_err);
                        wait(!o_rx_done);
                    end
                end
            join
            #(BIT_PERIOD * 2); // Guard time cho test thường
        end
    endtask

    // =========================================================================
    // 5. TASK: RUN STRESS TEST (TC12 - Back to Back)
    // =========================================================================
    task run_stress_test();
        begin
            $display("---------------------------------------------------------------");
            $display("Running: TC12 Stress (Back-to-Back 0x55 -> 0xAA)");
            
            i_num_bit_data = 2'b11; i_parity_en = 0; // Setup 8N1

            fork
                // --- Driver: Gửi 2 byte liền tù tì ---
                begin
                    // Byte 1: 0x55
                    send_byte(8'h55, 2'b11, 0, 0, 0, 1); 
                    // Byte 2: 0xAA (Ngay lập tức, không delay thêm)
                    send_byte(8'hAA, 2'b11, 0, 0, 0, 1);
                end

                // --- Monitor: Check 2 lần ---
                begin
                    // Check Byte 1
                    wait(o_rx_done);
                    if(o_data == 8'h55) $display("   [PASS 1/2] Received 0x55 correctly.");
                    else                 $display("   [FAIL 1/2] Expected 0x55, got 0x%h", o_data);
                    
                    wait(!o_rx_done); // Chờ done xuống

                    // Check Byte 2
                    wait(o_rx_done);
                    if(o_data == 8'hAA) $display("   [PASS 2/2] Received 0xAA correctly.");
                    else                 $display("   [FAIL 2/2] Expected 0xAA, got 0x%h", o_data);
                    
                    wait(!o_rx_done);
                end
            join
            #(BIT_PERIOD);
        end
    endtask

    // =========================================================================
    // 6. MAIN PROGRAM
    // =========================================================================
    initial begin
        $dumpfile("uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);

        rst_n = 0; i_rx_serial = 1; i_num_bit_data = 3; 
        #100 rst_n = 1; #100;

        $display("================ START FULL COVERAGE TESTING ================");

        //          Name            Wid   P_En P_Typ Stop  TxData InjErr Glitch ExpData ExpErr
        run_test("TC01 5-bit",      2'b00, 0,   0,    1,   8'h1F, 0,     0,     8'h1F,   0);
        run_test("TC02 6-bit",      2'b01, 0,   0,    1,   8'h2A, 0,     0,     8'h2A,   0);
        run_test("TC03 7-bit",      2'b10, 0,   0,    1,   8'h55, 0,     0,     8'h55,   0);
        run_test("TC04 8-bit",      2'b11, 0,   0,    1,   8'hFF, 0,     0,     8'hFF,   0);
        run_test("TC05 AllZero",    2'b11, 0,   0,    1,   8'h00, 0,     0,     8'h00,   0);
        run_test("TC06 EvenValid",  2'b11, 1,   0,    1,   8'h03, 0,     0,     8'h03,   0);
        run_test("TC07 EvenErr",    2'b11, 1,   0,    1,   8'h03, 1,     0,     8'h03,   1);
        run_test("TC08 OddValid",   2'b11, 1,   1,    1,   8'h03, 0,     0,     8'h03,   0);
        run_test("TC09 OddErr",     2'b11, 1,   1,    1,   8'h03, 1,     0,     8'h03,   1);
        run_test("TC10 2 Stop",     2'b11, 0,   0,    2,   8'hAA, 0,     0,     8'hAA,   0);
        
        // --- BỔ SUNG ---
        // TC11: Mismatch (Config DUT mặc định là 1 stop, nhưng Gửi 2 stop -> Vẫn phải nhận OK)
        run_test("TC11 Mismatch",   2'b11, 0,   0,    2,   8'h55, 0,     0,     8'h55,   0);
        
        // TC12: Stress Test (Chạy task riêng)
        run_stress_test();

        // TC13: Noise
        run_test("TC13 Glitch",     2'b11, 0,   0,    1,   8'h00, 0,     1,     8'h00,   0);

        $display("================ ALL TEST DONE ================");
        $finish;
    end

endmodule