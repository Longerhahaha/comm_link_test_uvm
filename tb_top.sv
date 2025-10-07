`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

`include "comm_link_pkg.sv"
`include "comm_link_dut.sv"

import comm_link_pkg::*;

module tb_top;
  localparam int DATA_WIDTH = comm_link_pkg::COMM_LINK_DATA_WIDTH;

  logic clk;
  logic rst_n;

  comm_link_if #(DATA_WIDTH) link_if (clk, rst_n);

  comm_link_dut #(.DATA_WIDTH(DATA_WIDTH)) dut (
    .link_if(link_if)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset generation
  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // Connect virtual interface and start the test
  initial begin
    uvm_config_db#(virtual comm_link_if)::set(null, "uvm_test_top.env.agent.driver", "vif", link_if);
    uvm_config_db#(virtual comm_link_if)::set(null, "uvm_test_top.env.agent.monitor", "vif", link_if);
    run_test("comm_link_test");
  end
endmodule : tb_top
