`timescale 1ns/1ps

import comm_link_pkg::*;

module comm_link_dut #(parameter int DATA_WIDTH = comm_link_pkg::COMM_LINK_DATA_WIDTH) (
  comm_link_if #(DATA_WIDTH) link_if
);
  logic [DATA_WIDTH-1:0] buffer;
  logic                   buffer_valid;

  assign link_if.tx_ready = !buffer_valid || (buffer_valid && link_if.rx_ready);
  assign link_if.rx_valid = buffer_valid;
  assign link_if.rx_data  = buffer;

  always_ff @(posedge link_if.clk or negedge link_if.rst_n) begin
    if (!link_if.rst_n) begin
      buffer       <= '0;
      buffer_valid <= 1'b0;
    end else begin
      if (link_if.tx_valid && link_if.tx_ready) begin
        buffer       <= link_if.tx_data;
        buffer_valid <= 1'b1;
      end else if (link_if.rx_ready && buffer_valid) begin
        buffer_valid <= 1'b0;
      end
    end
  end
endmodule : comm_link_dut
