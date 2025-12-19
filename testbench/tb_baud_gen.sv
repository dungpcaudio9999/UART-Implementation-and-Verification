`timescale 1ns/1ps
`include "../design/baud_gen.v"

module tb_baud_gen;
	/// -----	Signals	-----
	reg clk;
	reg rst_n;
	reg [15:0] i_divisor;
	wire rx_tick;
	wire tx_tick;

	// -----	Parameters	-----
	parameter CLK_PERIOD = 20; 		//50MHz

	// -----	Var measurement	-----
	integer last_rx_time = 0;
	integer measured_period = 0;

	// -----  Var for rx/tx_tick ratio check  ----- //
	integer rx_cnt = 0;
	integer check_ratio_en = 0;

	// -----	Instantiate DUT	-----
	baud_gen inst_baud_gen (
		.clk(clk),
		.rst_n(rst_n),
		.i_divisor(i_divisor),
		.rx_tick(rx_tick),
		.tx_tick(tx_tick)
	);
	
	// -----	Clock Gen	-----
	initial begin
		clk = 0;
		forever #(CLK_PERIOD/2) clk = ~clk;
	end

	// -----	Period Mesurement Logic	-----
	always @(posedge rx_tick) begin
		if(last_rx_time != 0) begin
			measured_period = $time - last_rx_time;
		end
		last_rx_time = $time;
	end

	// -----	TX/RX Ratio Logic Check	-----
	// Count rx_tick
	always @(posedge rx_tick) begin
		if(rst_n && check_ratio_en) begin
			rx_cnt = rx_cnt + 1;
		end
	end

	// when tx_tick is enable -> enough 16 rx_tick?
	always @(posedge tx_tick) begin
		if(rst_n && check_ratio_en) begin
			if(rx_cnt == 16) begin
				$display("[PASS TC_04] TX/RX Ratio is correct (16:1)");
			end else begin
				$display("[FAIL TC_04] Ratio Error! Expected 16 rx_ticks, got %0d", rx_cnt);
			end
			rx_cnt = 0; 	// reset rx_cnt for next count turn
		end
	end

	// -----	Task: Check Result	-----
	task uart_verify_baud(input [15:0] div_val, input [8*20-1:0] tc_name);
		integer expected_val;
		begin
			#1;
			// calculate the expected value
			expected_val = div_val * CLK_PERIOD;

			// wait for stable signal
			@(posedge rx_tick);
			@(posedge rx_tick);

			// compare period
			if(measured_period == expected_val) begin
				$display("[PASS %0s] Div=%0d | Expected=%0dns | Actual=%0dns", tc_name, div_val, expected_val, measured_period);
			end else begin
				$display("[FAIL %0s] Div=%0d | Expected=%0dns | Actual=%0dns", tc_name, div_val, expected_val, measured_period);
            end
		end
	endtask

	//==============================================================================
	//  SECTION: MAIN TEST
	//==============================================================================
	initial begin
		$display("\n===========================================");
        $display(" BAUD GENERATOR AUTOMATED TEST START");
        $display("===========================================");

		// -----	TC_01: RESET CHECK	-----
		$display("\n--- Starting TC_01: Reset Check ---");
	    rst_n = 0;
	    i_divisor = 325;
	    #200; // hold reset
	    
	    // check tick
	    if (rx_tick == 0 && tx_tick == 0) 
	        $display("[PASS TC_01] Outputs are 0 during reset");
	    else 
	        $display("[FAIL TC_01] Outputs are NOT 0 during reset!");

	    // release reset
	    rst_n = 1;
	    #100;
		
		// -----	TC_02: STANDARD 9600 bps	-----
		$display("\n--- Starting TC_02: Standard 9600 bps ---");
        i_divisor = 325;
        uart_verify_baud(325, "TC_02");

        
        #100;
        rst_n = 0;
	    #100;
	    rst_n = 1;
	    #100;

		// -----	TC_03: HIGH SPEED 115200 bps	-----
		$display("\n--- Starting TC_03: High Speed 115200 bps ---");
        i_divisor = 27;
        uart_verify_baud(27, "TC_03");

        #100;
        rst_n = 0;
	    #100;
	    rst_n = 1;
	    #100;

		// -----	TC_04: TX/RX RATIO CHECK	-----
		$display("\n--- Starting TC_04: TX/RX Ratio Check ---");
		i_divisor = 100;
		rx_cnt = 0;
		check_ratio_en = 1;
	

		@(posedge tx_tick);
		@(posedge tx_tick);
		
		check_ratio_en = 0;
			

		#100;
        rst_n = 0;
	    #100;
	    rst_n = 1;
	    #100;

		// -----	TC_05: DYNAMIC SWITCHING	-----
		$display("\n--- Starting TC_05: Dynamic Switch ---");
		i_divisor = 100;
		i_divisor = 50;
		
		uart_verify_baud(50, "TC_05");

		#100;
        rst_n = 0;
	    #100;
	    rst_n = 1;
	    #100;

		// -----	TC_06: MIN DIVISOR (Max Speed)	-----
		$display("\n--- Starting TC_06: Min Divisor = 2 ---");
        i_divisor = 2;
        uart_verify_baud(2, "TC_06");

        #100;
        rst_n = 0;
	    #100;
	    rst_n = 1;
	    #100;

		// -----	TC_07: RANDOM STRESS TEST	-----
		$display("\n--- Starting TC_07: Random Stress Test ---");
        repeat(20) begin
            i_divisor = $urandom_range(10, 500);
            uart_verify_baud(i_divisor, "TC_07_Rand");
        end

		#100;
        $display("\n===========================================");
        $display("   ALL TESTS COMPLETED. CHECK FOR ERRORS   ");
        $display("===========================================");
		$finish;
	end

	initial begin
        $dumpfile("waveform/baud_gen.vcd");
        $dumpvars(0, tb_baud_gen);
    end

endmodule