# UART-Implementation-and-Verification
Implement UART Protocol Communication in Verilog and write testbench to verify the functions

# Tổng hợp lệnh iverilog
# Compile code
iverilog -o ofile/sim.out uart_core.v baud_gen.v uart_tx.v uart_rx.v fifo.v 

# chạy file tb_uart_core.sv
iverilog -g2012 \
  -o ofile/sim.out \
  tb_uart_core.sv \
  ../design/uart_core.v \
  ../design/uart_tx.v \
  ../design/uart_rx.v \
  ../design/baud_gen.v \
  ../design/fifo.v
