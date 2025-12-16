`timescale 1ns/1ps
`include "../design/fifo.v"

module tb_fifo;
	/// -----  Signals  ----- //
	reg clk;
	reg rst_n;
	reg i_wr_en;
	reg [7:0] i_wr_data;
	wire o_full;
	wire o_almost_full;
	reg i_rd_en;
	wire [7:0] o_rd_data;
	wire o_empty;

	// -----  Parameters  ----- //
	localparam CLK_PERIOD = 20;
	parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 4;
    parameter ALMOST_FULL_THRESH = 14;

	// -----  Instantiate DUT  ----- //
	fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ALMOST_FULL_THRESH(ALMOST_FULL_THRESH)
    ) inst_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .i_wr_en(i_wr_en),
        .i_wr_data(i_wr_data),
        .o_full(o_full),
        .o_almost_full(o_almost_full),
        .i_rd_en(i_rd_en),
        .o_rd_data(o_rd_data),
        .o_empty(o_empty)
    );

	// -----  Clock Gen  ----- //
	initial begin
		clk = 0;
		forever #(CLK_PERIOD/2) clk = ~clk;
	end

	// -----  Task  ----- //
	// Task write to FIFO
	task write_fifo(input [7:0] data);
		begin
			if(o_full) begin
				$display("[WARNING] FIFO Full! Cannot write %h", data);
			end else begin
				@(negedge clk);
				i_wr_en = 1;
				i_wr_data = data;
				@(negedge clk);
				i_wr_en = 0;
			end
		end
	endtask

	// Task read and check
	task read_and_check(input [7:0] expected_data);
		begin
            if (o_empty) begin
                $error("[FAIL] FIFO Empty! Cannot read expected %h", expected_data);
            end else begin
                // FIFO: FWFT -> check data before pulse rd_en
                #1; 
                if (o_rd_data != expected_data) begin
                    $error("[FAIL] Data Mismatch! Expected: %h, Got: %h", expected_data, o_rd_data);
                end else begin
                    $display("[PASS] Read Data: %h (Match)", o_rd_data);
                end
                
                // pulse read -> pointer to next
                @(negedge clk);
                i_rd_en = 1;
                @(negedge clk);
                i_rd_en = 0;
            end
        end
	endtask

	///==============================================================================
	//  SECTION: MAIN TEST SCENARIO
	//==============================================================================
	integer i;
    initial begin
        $display("=== START FIFO TEST ===");
        
        // --- TC_01: Init & Reset ---
        rst_n = 0; i_wr_en = 0; i_rd_en = 0; i_wr_data = 0;
        #50;
        if (o_empty === 1 && o_full === 0) 
            $display("[PASS TC_01] Reset Check OK");
        else 
            $error("[FAIL TC_01] Reset Failed");
        rst_n = 1;
        #20;

        // --- TC_02: Basic Write & Read ---
        $display("\n--- TC_02: Write 0xAA, Read 0xAA ---");
        write_fifo(8'hAA);
        #20;
        if (o_empty === 0) $display("[INFO] FIFO not empty, good.");
        read_and_check(8'hAA);
        if (o_empty === 1) $display("[PASS TC_02] Empty again after read.");

        // --- TC_03 & TC_04: Fill FIFO & Check Flags ---
        $display("\n--- TC_03 & TC_04: Fill FIFO (16 items) ---");
        // Ghi 16 giá trị: 0x10, 0x11, ... 0x1F
        for (i = 0; i < 16; i = i + 1) begin
            write_fifo(8'h10 + i);
            // Check Almost at 14 (written 14 byte: index 0-13)
            if (i == 13) begin 
                #1; // Wait logic update
                if (o_almost_full) $display("[PASS TC_04] Almost Full Triggered at 14 items");
                else               $error("[FAIL TC_04] Almost Full MISSED at 14 items");
            end
        end

        #1;
        if (o_full) $display("[PASS TC_03] FIFO Full Flag OK");
        else        $error("[FAIL TC_03] FIFO Should be FULL now!");

        // Overflow protection
        write_fifo(8'h99); // not allow

        // --- TC_05: Empty FIFO & Verify Data ---
        $display("\n--- TC_05: Empty FIFO & Verify Order ---");
        for (i = 0; i < 16; i = i + 1) begin
            read_and_check(8'h10 + i); // Phải đọc ra đúng thứ tự 0x10 -> 0x1F
        end

        #1;
        if (o_empty) $display("[PASS TC_05] FIFO Empty Flag OK");
        else         $error("[FAIL TC_05] FIFO Should be EMPTY now!");

        // --- TC_06: POINTER ROLLOVER (Test vòng lặp) ---
        $display("\n--- TC_06: Pointer Rollover Test ---");
        // Now FIFO empty
        // Write 10 bytes, read 10 bytes
        // Total write 30 byte -> Pointer roll over at least once (Depth=16).
        for (integer k = 0; k < 3; k = k + 1) begin
            // Ghi 10
            for (i = 0; i < 10; i = i + 1) write_fifo(8'hA0 + k*16 + i);
            // Đọc 10
            for (i = 0; i < 10; i = i + 1) read_and_check(8'hA0 + k*16 + i);
        end
        $display("[PASS TC_06] Pointer Rollover OK");

        #50; rst_n = 0;
        #50; rst_n = 1;

        // --- TC_07: SIMULTANEOUS READ & WRITE (Vừa đọc vừa ghi) ---
        $display("\n--- TC_07: Simultaneous Read & Write ---");
        // 1. Write some bytes
        write_fifo(8'h11);
        write_fifo(8'h22);
        write_fifo(8'h33);
        // count = 3.

        // 2. Enable cả WR adn RD both
        @(negedge clk);
        i_wr_en = 1; i_wr_data = 8'h44; 
        i_rd_en = 1;

        #1;
        $display("[DEBUG] Checking Data NOW: %h", o_rd_data);
        
        if (o_rd_data == 8'h11) 
            $display("[PASS] Simultaneous Data Out OK (Got 0x11)");
        else 
            $error("[FAIL] Simult. Data mismatch. Expected 0x11, Got %h", o_rd_data);
        // -------------------------------------------------------

        @(negedge clk); // Data to 0x22
        i_wr_en = 0; i_rd_en = 0;
        
        #1;
        $display("[DEBUG] Data after clock: %h", o_rd_data); // 0x22

        // 3. Check logic:
        // - Count=3 (In 1, Out 1).
        // - Data out in this period: 0x11.
        // - Next byte in queue line: 0x22.
        // - Byte 0x44: last 
        
        #10;
        // Read to check order
        read_and_check(8'h22);
        read_and_check(8'h33);
        read_and_check(8'h44);
        
        if (o_empty) $display("[PASS TC_07] Simultaneous R/W Logic OK");
        else         $error("[FAIL TC_07] Count Logic wrong after Simult. R/W");

        
        // --- TC_08: RANDOM STRESS TEST (Tra tấn ngẫu nhiên) ---
        $display("\n--- TC_08: Random Stress Test ---");
        rst_n = 0; #10; rst_n = 1; #10; // Reset sạch sẽ
        
        // Random write, read or both
        // Run 1000 
        begin
            reg [7:0] queue [$]; // Goden Model
            reg [7:0] val_in, val_out, val_exp;
            reg do_wr, do_rd;
            
            repeat(1000) begin
                @(negedge clk);
                do_wr = $urandom_range(0, 1);
                do_rd = $urandom_range(0, 1); 
                val_in = $urandom;

                // Cập nhật tín hiệu
                i_wr_en = do_wr && !o_full;  // write if not full 
                i_rd_en = do_rd && !o_empty; // read if not empty 
                i_wr_data = val_in;

                // Update Golden Model (Queue Testbench)
                if (i_wr_en) queue.push_back(val_in);
                
                // Check read data
                if (i_rd_en) begin
                    // 1. Lấy giá trị kỳ vọng từ mô hình mẫu (Queue)
                    if (queue.size() == 0) begin
                        $error("[FAIL] Testbench Logic Error: Queue empty but i_rd_en is HIGH");
                    end else begin
                        val_exp = queue.pop_front();
                        
                        // 2. SO SÁNH NGAY LẬP TỨC (QUAN TRỌNG)
                        // Vì FIFO là FWFT, dữ liệu o_rd_data đang hiện sẵn ở đầu ra
                        // ngay lúc ta quyết định đọc (trước khi clock active).
                        #1; // Delay 1 xíu để tín hiệu ổn định
                        if (o_rd_data != val_exp) begin
                            $error("[FAIL TC_08] Data Mismatch! Expected: %h, Got: %h", val_exp, o_rd_data);
                        end else begin
                            $display("Good: %h", o_rd_data);
                        end
                    end
                end
            end
            i_wr_en = 0; i_rd_en = 0;
            $display("[PASS TC_08] Survived 1000 cycles of Random Stress");
        end
        
	
	   $display("\n=== ALL TESTS COMPLETED ===");
        $finish;
    end

    // Dump sóng
    initial begin
        $dumpfile("fifo.vcd");
        $dumpvars(0, tb_fifo);
    end
endmodule