/////////////////////////////////////////////////////////////////////////////////
//
//  Module Name:  UART_TX
//  Project:      UART Implementation and Verification
//  Author:       DungPC
//  Date:         12/2025
//  Description:  Description here...
//
////////////////////////////////////////////////////////////////////////////////

module uart_tx (
	input wire clk,    // Clock
	input wire rst_n,  // Asynchronous reset active low
    input wire tx_tick,
	input wire [1:0] i_num_bit_data,
	input wire i_parity_en,
	input wire i_parity_type,
	input wire [7:0] i_data,
	input wire i_tx_start,
	output reg o_tx_done,
	input wire i_cts_n,
	output reg o_tx_serial
	
);

//==============================================================================
//  SECTION: Parameter
//==============================================================================
	localparam IDLE = 3'd0;
	localparam START = 3'd1;
	localparam DATA = 3'd2;
	localparam PARITY = 3'd3;
	localparam STOP = 3'd4;

//==============================================================================
//  SECTION: Internal
//==============================================================================
	reg [2:0] state, next_state;
	reg [2:0] bit_cnt;
	reg [7:0] shift_reg;
	reg tx_reg, tx_next;
	reg parity_bit;

	// bit limit for number of bits data -> 00:5,01:6,10:7,11:8
	wire [2:0] bit_limit = 3'd4 + {1'b0, i_num_bit_data};

//==============================================================================
//  SECTION: State Machine
//==============================================================================
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			state <= IDLE;
			tx_reg <= 1'b1;
			shift_reg <= 0;
			bit_cnt <= 0;
			o_tx_serial <= 1'b1;
			parity_bit <= 0;
		end else begin
			state <= next_state;
			tx_reg <= tx_next;
			o_tx_serial <= tx_reg;

			// -----	Update count/shift var at right state	-----
			if(state == IDLE && i_tx_start && !i_cts_n) begin
				// Load data to shift_reg
				shift_reg <= i_data;

				// Calculate parity
				case (bit_limit)
					2'b00: parity_bit <= ^i_data[4:0];
					2'b01: parity_bit <= ^i_data[5:0];
					2'b10: parity_bit <= ^i_data[6:0];
					2'b11: parity_bit <= ^i_data[7:0];				
				endcase

				// Parity type -> num bit 1 -> ODD: 1, EVEN:0
				if(i_parity_type) begin
					parity_bit <= ~parity_bit; 	// ODD parity
				end
			end else if(state == START) begin
				bit_cnt <= 0;
			end else if(state == DATA && tx_tick) begin
				shift_reg <= shift_reg >> 1; 	// shift right 1 bit
				bit_cnt <= bit_cnt + 1;
			end
		end
	end

//==============================================================================
//  SECTION: Next state logic
//==============================================================================
	always @(state or tx_tick or i_tx_start or i_cts_n or parity_bit or tx_reg) begin
		// initial
		next_state = state;
		tx_next = tx_reg;
		o_tx_done = 1'b0;     // default
		case(state)
			IDLE: begin
				tx_next = 1'b1;
				if(i_tx_start && !i_cts_n) begin
					next_state = START;
				end
			end
			START: begin
				if(tx_tick) begin
					tx_next = 1'b0;
					next_state = DATA;
				end
			end
			DATA: begin
                if(tx_tick) begin
                    tx_next = shift_reg[0];
                    if(bit_cnt == bit_limit) begin
                        if(i_parity_en) begin
                            next_state = PARITY;
                        end else begin
                            next_state = STOP;
                        end
                    end
                end
			end
			PARITY: begin
                if(tx_tick) begin
                    tx_next = parity_bit;
                    next_state = STOP;
                end
			end
			STOP: begin
                if(tx_tick) begin
                    tx_next = 1'b1;
                    next_state = IDLE;
                    o_tx_done = 1'b1;
                end
			end
			default: next_state = IDLE;
	   endcase
    end
endmodule