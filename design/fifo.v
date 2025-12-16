module fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4,
    parameter ALMOST_FULL_THRESH = 14
)(
    input  wire clk,
    input  wire rst_n,
    
    // Write
    input  wire i_wr_en,
    input  wire [DATA_WIDTH-1:0] i_wr_data,
    output wire o_full,
    output wire o_almost_full, 

    // Read
    input  wire i_rd_en,
    output wire [DATA_WIDTH-1:0] o_rd_data,
    output wire o_empty
);

    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1]; 	// 8 x 16
    reg [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
    reg [ADDR_WIDTH:0] count; 

    // Write Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) wr_ptr <= 0;
        else if (i_wr_en && !o_full) begin
            mem[wr_ptr] <= i_wr_data;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // Read Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rd_ptr <= 0;
        else if (i_rd_en && !o_empty) begin
            rd_ptr <= rd_ptr + 1;
        end
    end

    // Counter Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) count <= 0;
        else begin
            case ({i_wr_en && !o_full, i_rd_en && !o_empty})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: count <= count;
            endcase
        end
    end

    // Outputs
    assign o_rd_data     = mem[rd_ptr];
    assign o_full        = (count == (1 << ADDR_WIDTH));
    assign o_empty       = (count == 0);
    assign o_almost_full = (count >= ALMOST_FULL_THRESH);

endmodule