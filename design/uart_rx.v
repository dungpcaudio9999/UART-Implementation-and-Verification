////////////////////////////////////////////////////////////////////////////////
//
//  Module Name:  UART_RX
//  Project:      UART Implementation and Verification
//  Author:       DungPC
//  Date:         Current Date
//  Description:  Description here...
//
////////////////////////////////////////////////////////////////////////////////

module uart_rx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_tick,        
    input  wire [1:0] i_num_bit_data,
    input  wire       i_parity_en,
    input  wire       i_parity_type,
    input  wire       i_rx_serial,
    output reg [7:0]  o_data,
    output reg        o_rx_done,
    output reg        o_parity_err
);
    // Parameters
    localparam IDLE = 3'd0; 
    localparam START = 3'd1;
    localparam DATA = 3'd2;
    localparam PARITY=3'd3; 
    localparam STOP=3'd4;

    //Internal
    reg [2:0] state, next_state;
    reg [3:0] tick_cnt;
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg       calc_parity;
    wire      expected_parity;
    reg [1:0] sync_reg;
    wire      rx_synced;
    wire [3:0] bit_limit = 4'd4 + {2'b00, i_num_bit_data};

    // Sync input
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) sync_reg <= 2'b11;
        else sync_reg <= {sync_reg[0], i_rx_serial};
    end
    assign rx_synced = sync_reg[1];
    assign expected_parity = i_parity_type ? ~calc_parity : calc_parity;

    // --- State Machine ---
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= IDLE;
            tick_cnt <= 0;
            bit_cnt <= 0;
            shift_reg <= 0;
            o_data <= 0;
            o_rx_done <= 0;
            o_parity_err <= 0;
            calc_parity <= 0;
        end else begin
            state <= next_state;

            // Update tick_cnt (Dùng rx_tick)
            if(state == IDLE) tick_cnt <= 0;
            else if(next_state == START && state == IDLE) tick_cnt <= 0; 
            else if(next_state == DATA && state == START) tick_cnt <= 0;
            else if(rx_tick) tick_cnt <= tick_cnt + 1; 

            if(state == IDLE || state == START) bit_cnt <= 0;

            // Logic lấy mẫu (tick 7)
            if(state == DATA && rx_tick && tick_cnt == 7) begin
                shift_reg <= {rx_synced, shift_reg[7:1]};
                if(bit_cnt == 0) calc_parity <= rx_synced;
                else              calc_parity <= calc_parity ^ rx_synced;
            end
            
            // Logic cập nhật bit (tick 15)
            if(state == DATA && rx_tick && tick_cnt == 15) begin
                bit_cnt <= bit_cnt + 1;
            end

            // Check Parity
            if(state == PARITY && rx_tick && tick_cnt == 7) begin
                o_parity_err <= (rx_synced != expected_parity);
            end
            if(state == IDLE) o_parity_err <= 0;
            
            o_rx_done <= (state == STOP && rx_tick && tick_cnt == 15);
            if(state == STOP && rx_tick && tick_cnt == 15) begin
                case (i_num_bit_data)
                    2'b00: o_data <= {3'b0, shift_reg[7:3]};
                    2'b01: o_data <= {2'b0, shift_reg[7:2]};
                    2'b10: o_data <= {1'b0, shift_reg[7:1]};
                    2'b11: o_data <= shift_reg;
                endcase
            end
        end
    end

    // --- Next State Logic ---
    always @(state or rx_synced or rx_tick or tick_cnt or bit_cnt or bit_limit or i_parity_en) begin
        next_state = state;
        case (state)
            IDLE:   if(rx_synced == 1'b0) next_state = START;
            
            START: begin
                /*
                if(rx_tick && tick_cnt == 7 && rx_synced == 1'b1) // Sample giữa START bit
                            next_state = IDLE;
                if(rx_tick && tick_cnt == 15 && rx_synced == 1'b0) 
                    next_state = DATA;
                */
                if (rx_tick && tick_cnt == 15) 
                    next_state = DATA;
                else
                    next_state = START;
            end
            
            DATA:   if(rx_tick && tick_cnt == 15) begin
                        if(bit_cnt == bit_limit) 
                            next_state = i_parity_en ? PARITY : STOP;
                    end
            
            PARITY: if(rx_tick && tick_cnt == 15) next_state = STOP;
            STOP:   if(rx_tick && tick_cnt == 15) next_state = IDLE;
        endcase
    end
endmodule