module baud_gen (
    input  wire clk,
    input  wire rst_n,
    input  wire [15:0] i_divisor, 		// 325 for 9600bps
    output wire rx_tick,
    output wire tx_tick
);

    reg [15:0] count_reg;
    reg [3:0] tick_cnt;

    reg rx_reg;
    reg tx_reg;


    // -----	Create rx_tick (16x baud)	-----
    // count from 0 to i_divisor - 1
    always @(posedge clk or negedge rst_n) begin
    	if(!rst_n) begin
    		count_reg <= 0;
    		rx_reg <= 1'b0;
    	end else begin
    		if(count_reg >= (i_divisor - 16'd1)) begin
    			count_reg <= 0;
    			rx_reg <= 1'b1;
    		end else begin
    			count_reg <= count_reg + 1;
    			rx_reg <= 1'b0;
    		end
    	end
    end

    // -----	Create tx_tick (1x baud)	-----
    always @(posedge clk or negedge rst_n) begin
    	if(!rst_n) begin
    		tick_cnt <= 0;
    		tx_reg <= 0;
    	end else if(rx_tick) begin
    		tick_cnt <= tick_cnt + 1;

    		if(tick_cnt == 4'd15) begin
    			tx_reg <= 1'b1;
    		end else begin
    			tx_reg <= 1'b0;
    		end
    	end else begin
    		tx_reg <= 1'b0;
    	end
    end

    assign rx_tick = rx_reg;
    assign tx_tick = tx_reg;
endmodule