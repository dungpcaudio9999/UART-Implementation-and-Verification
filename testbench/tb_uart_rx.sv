`timescale 1ns/1ps
`include "uart_rx.v"

module tb_uart_rx;
	reg clk;    // Clock
	reg rst_n;  // Asynchronous reset active low
	reg rx_tick;
	reg [1:0] i_num_bit_data;
	reg i_stop_bit;
	reg i_parity_en;
	reg i_parity_type;
	reg i_rx_serial;
	wire [7:0] o_data;
	wire o_rx_done;
	wire o_parity_err;

    // Parameters
    localparam IDLE 	= 3'd0; 
    localparam START 	= 3'd1;
    localparam DATA 	= 3'd2;
    localparam PARITY 	= 3'd3; 
    localparam STOP 	= 3'd4;
	
	parameter DIVISOR = 325;
	parameter BIT_PERIOD = 104167;

    //==============================================================================
    //  SECTION: Clock and tick Generator
    //==============================================================================
    initial clk = 0;
    always #10 clk = ~clk;

    reg [15:0] tick_counter;
    always @(posedge clk or negedge rst_n) begin
    	if(!rst_n) begin
    		tick_counter <= 0;
    		rx_tick <= 0;
    	end else begin
    		if(tick_counter >= DIVISOR) begin
    			tick_counter <= 0;
    			rx_tick <= 1;
    		end else begin
    			tick_counter <= tick_counter + 1;
    			rx_tick <= 0;
    		end
    	end
    end

    //==============================================================================
    //  SECTION: DUT Instatiation
    //==============================================================================
    uart_rx inst_uart_rx (
    	.clk(clk),
    	.rst_n(rst_n),
    	.rx_tick(rx_tick),
    	.i_num_bit_data(i_num_bit_data),
    	.i_stop_bit(i_stop_bit),
    	.i_parity_en(i_parity_en),
    	.i_parity_type(i_parity_type),
    	.i_rx_serial(i_rx_serial),
    	.o_data(o_data),
    	.o_rx_done(o_rx_done),
    	.o_parity_err(o_parity_err)
    );

    //==============================================================================
    //  SECTION: Task for verification
    //==============================================================================
    task uart_send_frame(
    	input [7:0] data,
    	input [1:0] num_bit,
    	input parity_en,
    	input parity_type,
    	input inject_err,
    	input stop_bit
    );
		integer i;
		integer limit;
		reg calc_p;
		begin
			// cho các tín hiệu của task đi qua DUT
			i_num_bit_data = num_bit;
			i_parity_en = parity_en;
			i_parity_type = parity_type;
			i_stop_bit = stop_bit;

			// xác định số bit DATA
			case(num_bit)
				2'b00: limit = 5;
				2'b01: limit = 6;
				2'b10: limit = 7;
				2'b11: limit = 8;
				default: limit = 8;
			endcase
		
			// tính toán parity mong đợi
			calc_p = 0;
			for(i = 0; i < limit; i = i + 1) begin
				calc_p = calc_p ^ data[i]; 		// dùng xor vì cứ số chẵn 1 cộng vào với nhau thì bằng 0, số lẻ thì là 1
			end
			if(parity_type == 1'b0) begin 		// even parity
				calc_p = calc_p;
			end else begin
				calc_p = ~calc_p;
			end
			
			// Nếu muốn tiêm lỗi
			if(inject_err) calc_p = ~calc_p;
			
			// display informations
			$display("[TB Send] Data: 0x%h | Mode: %0d-bit| ParityEn: %b | ErrInject: %b", data, limit, parity_en, inject_err);
		
			// Bắt đầu gửi 
			// Start bit
			i_rx_serial = 0;
			#(BIT_PERIOD);
			
			// Data
			for(i = 0; i < limit; i = i + 1) begin
				i_rx_serial = data[i];
				#(BIT_PERIOD);
			end
			
			// Parity bit
			if(parity_en) begin
				i_rx_serial = calc_p;
				#(BIT_PERIOD);
			end
			
			// Stop bit
			i_rx_serial = 1;
			#(BIT_PERIOD);
			
			// Guard time
			#(BIT_PERIOD);
		end
    endtask
	
	//==============================================================================
    //  SECTION: Testbench 
    //==============================================================================
    initial begin
    	// =========== Begin testbench ===========
    	$display("=================== UART RX UNIT TEST ===================");

    	rst_n = 0;
    	// Intialization
    	i_rx_serial = 1;
    	i_num_bit_data = 2'b11;
    	i_parity_en = 0;
    	i_parity_type = 0;
    	i_stop_bit = 0;

    	#100;
    	rst_n = 1;
    	#100;

    	// =========== Test 1 ===========
    	$display("\n--- Test 1 (data 0xA5) ---");
    	fork
    		begin
    			uart_send_frame(8'hA5, 2'b11, 0, 0, 0, 0);

    		end
    		begin
    			wait(o_rx_done);
    			if(o_data == 8'hA5 && o_rx_done == 1) begin
    				$display("[PASS] Received 0xA5 correctly");
    			end else begin
    				$display("[FAIL] Expected: 0xA5, Got 0x%h", o_data);
    			end
    		end
    	join
    	
    	#1000;
    	$display("ALL TEST FINISHED");
    	$finish;
    	
    end
    initial begin
        $dumpfile("uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
    end

endmodule 