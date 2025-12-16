////////////////////////////////////////////////////////////////////////////////
//
//  Module Name:  UART_CORE
//  Project:      UART Implementation and Verification
//  Author:       DungPC
//  Description:  Top-level module connecting TX, RX, FIFO and Baud Generator.
//                - Supports buffering (16-byte FIFO).
//                - Automatic flow control (RTS/CTS).
//                - Configurable Baudrate, Parity, Data bits.
//
////////////////////////////////////////////////////////////////////////////////
/*
`include "uart_tx.v"
`include "uart_rx.v"
`include "baud_gen.v"
`include "fifo.v"
*/

module uart_core (
    // -------------------------------------------------------------------------
    // 1. System Interface
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // 2. Configuration (From Register File / CPU)
    // -------------------------------------------------------------------------
    input  wire [15:0] i_divisor,       // Baudrate divisor (325 for 9600 @ 50MHz)
    input  wire [1:0]  i_num_bit_data,  // 00:5, 01:6, 10:7, 11:8 bits
    input  wire        i_parity_en,     // 1: Enable Parity
    input  wire        i_parity_type,   // 0: Even, 1: Odd

    // -------------------------------------------------------------------------
    // 3. CPU Interface (Data & Status)
    // -------------------------------------------------------------------------
    // --- TX Interface ---
    input  wire [7:0]  i_cpu_txd,       // Data to send
    input  wire        i_tx_wr,         // Write enable
    output wire        o_tx_full,       // TX FIFO Full status

    // --- RX Interface ---
    output wire [7:0]  o_cpu_rxd,       // Data received
    input  wire        i_rx_rd,         // Read enable
    output wire        o_rx_empty,      // RX FIFO Empty status
    output wire        o_parity_err,    // Parity error flag (from latest byte)

    // -------------------------------------------------------------------------
    // 4. Physical Interface (Connect to Pads/Pins)
    // -------------------------------------------------------------------------
    output wire        o_pedev_txd,     // Serial Transmit Data
    input  wire        i_pedev_rxd,     // Serial Receive Data
    input  wire        i_cts_n,         // Clear To Send (Active Low) - Input
    output wire        o_rts_n          // Request To Send (Active Low) - Output
);

    // =========================================================================
    // INTERNAL SIGNALS
    // =========================================================================
    
    // Baud Rate Ticks
    wire tx_tick; // 1x Baud
    wire rx_tick; // 16x Baud

    // TX Internal Connections
    wire [7:0] tx_fifo_out;
    wire       tx_fifo_empty;
    wire       tx_done_tick;    // UART TX finished sending a byte

    // RX Internal Connections
    wire [7:0] rx_data_out;     // Data from UART RX -> FIFO
    wire       rx_done_tick;    // UART RX finished receiving a byte
    wire       rx_fifo_almost_full; // Trigger for RTS

    // =========================================================================
    // MODULE INSTANTIATION
    // =========================================================================

    // -------------------------------------------------------------------------
    // 1. Baud Rate Generator 
    // -------------------------------------------------------------------------
    baud_gen u_baud_gen (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_divisor  (i_divisor),
        .rx_tick    (rx_tick),
        .tx_tick    (tx_tick)
    );

    // -------------------------------------------------------------------------
    // 2. TX FIFO (Buffer for Transmission) 
    // -------------------------------------------------------------------------
    fifo #(
        .DATA_WIDTH(8), 
        .ADDR_WIDTH(4),       // Depth = 16
        .ALMOST_FULL_THRESH(14)
    ) u_tx_fifo (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // Write Side (CPU)
        .i_wr_en        (i_tx_wr),
        .i_wr_data      (i_cpu_txd),
        .o_full         (o_tx_full),
        .o_almost_full  (), // Not used for TX

        // Read Side (UART TX)
        .i_rd_en        (tx_done_tick), // Pop next byte when current is done
        .o_rd_data      (tx_fifo_out),
        .o_empty        (tx_fifo_empty)
    );

    // -------------------------------------------------------------------------
    // 3. UART Transmitter 
    // -------------------------------------------------------------------------
    uart_tx u_uart_tx (
        .clk            (clk),
        .rst_n          (rst_n),
        .tx_tick        (tx_tick),
        
        // Config
        .i_num_bit_data (i_num_bit_data),
        .i_parity_en    (i_parity_en),
        .i_parity_type  (i_parity_type),
        
        // Data & Handshake
        .i_data         (tx_fifo_out),
        .i_tx_start     (!tx_fifo_empty), // Auto-start if FIFO has data (FWFT logic)
        .o_tx_done      (tx_done_tick),   // Triggers FIFO Read
        
        // Flow Control & Physical
        .i_cts_n        (i_cts_n),
        .o_tx_serial    (o_pedev_txd)
    );

    // -------------------------------------------------------------------------
    // 4. UART Receiver 
    // -------------------------------------------------------------------------
    uart_rx u_uart_rx (
        .clk            (clk),
        .rst_n          (rst_n),
        .rx_tick        (rx_tick),
        
        // Config
        .i_num_bit_data (i_num_bit_data),
        .i_parity_en    (i_parity_en),
        .i_parity_type  (i_parity_type),
        
        // Physical
        .i_rx_serial    (i_pedev_rxd),
        
        // Output
        .o_data         (rx_data_out),
        .o_rx_done      (rx_done_tick),   // Triggers FIFO Write
        .o_parity_err   (o_parity_err)
    );

    // -------------------------------------------------------------------------
    // 5. RX FIFO (Buffer for Reception) 
    // -------------------------------------------------------------------------
    fifo #(
        .DATA_WIDTH(8), 
        .ADDR_WIDTH(4),       // Depth = 16
        .ALMOST_FULL_THRESH(14)
    ) u_rx_fifo (
        .clk            (clk),
        .rst_n          (rst_n),
        
        // Write Side (UART RX)
        .i_wr_en        (rx_done_tick),
        .i_wr_data      (rx_data_out),
        .o_full         (),               // Internal overflow handled by FIFO logic
        .o_almost_full  (rx_fifo_almost_full), // Use for RTS generation

        // Read Side (CPU)
        .i_rd_en        (i_rx_rd),
        .o_rd_data      (o_cpu_rxd),
        .o_empty        (o_rx_empty)
    );

    // =========================================================================
    // FLOW CONTROL LOGIC
    // =========================================================================
    // RTS_N (Output): Tells the other device to STOP sending.
    // If RX FIFO is almost full (>= 14 bytes), assert RTS (Active Low -> 1)
    
    assign o_rts_n = rx_fifo_almost_full;

endmodule