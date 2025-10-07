`ifndef COMM_LINK_PKG_SV
`define COMM_LINK_PKG_SV

`timescale 1ns/1ps

package comm_link_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int COMM_LINK_DATA_WIDTH = 32;

  // ---------------------------------------------------------------------------
  // Interface definition for the communication link
  // ---------------------------------------------------------------------------
  interface comm_link_if #(parameter int DATA_WIDTH = COMM_LINK_DATA_WIDTH) (input logic clk, input logic rst_n);
    logic                  tx_valid;
    logic                  tx_ready;
    logic [DATA_WIDTH-1:0] tx_data;

    logic                  rx_valid;
    logic                  rx_ready;
    logic [DATA_WIDTH-1:0] rx_data;

    // Driver modport: drives TX side, observes RX ready
    modport drv_mp (
      input  clk,
      input  rst_n,
      output tx_valid,
      output tx_data,
      input  tx_ready,
      input  rx_valid,
      input  rx_data,
      output rx_ready
    );

    // Monitor modport: observes both TX and RX sides
    modport mon_mp (
      input clk,
      input rst_n,
      input tx_valid,
      input tx_ready,
      input tx_data,
      input rx_valid,
      input rx_ready,
      input rx_data
    );
  endinterface : comm_link_if

  // ---------------------------------------------------------------------------
  // Sequence item representing one payload transfer through the link
  // ---------------------------------------------------------------------------
  class comm_link_seq_item extends uvm_sequence_item;
    rand bit [COMM_LINK_DATA_WIDTH-1:0] data;
    rand int unsigned idle_cycles;

    constraint c_idle_cycles { idle_cycles < 5; }

    `uvm_object_utils_begin(comm_link_seq_item)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(idle_cycles, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "comm_link_seq_item");
      super.new(name);
    endfunction : new
  endclass : comm_link_seq_item

  // ---------------------------------------------------------------------------
  // Sequence: random stream of packets
  // ---------------------------------------------------------------------------
  class comm_link_sequence extends uvm_sequence #(comm_link_seq_item);
    rand int unsigned num_transactions;

    constraint c_num_transactions { num_transactions inside {[5:20]}; }

    `uvm_object_utils(comm_link_sequence)

    function new(string name = "comm_link_sequence");
      super.new(name);
    endfunction : new

    virtual task body();
      comm_link_seq_item tr;
      repeat (num_transactions) begin
        tr = comm_link_seq_item::type_id::create("tr");
        if (!tr.randomize()) begin
          `uvm_error(get_type_name(), "Randomization failed for comm_link_seq_item")
        end
        start_item(tr);
        finish_item(tr);
      end
    endtask : body
  endclass : comm_link_sequence

  // ---------------------------------------------------------------------------
  // Sequencer
  // ---------------------------------------------------------------------------
  class comm_link_sequencer extends uvm_sequencer #(comm_link_seq_item);
    `uvm_component_utils(comm_link_sequencer)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction : new
  endclass : comm_link_sequencer

  // ---------------------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------------------
  class comm_link_driver extends uvm_driver #(comm_link_seq_item);
    `uvm_component_utils(comm_link_driver)

    virtual comm_link_if drv_if;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual comm_link_if)::get(this, "", "vif", drv_if)) begin
        `uvm_fatal(get_type_name(), "Virtual interface not found for driver")
      end
    endfunction : build_phase

    virtual task reset_phase(uvm_phase phase);
      super.reset_phase(phase);
      phase.raise_objection(this);
      drv_if.tx_valid <= 1'b0;
      drv_if.tx_data  <= '0;
      drv_if.rx_ready <= 1'b0;
      wait (drv_if.rst_n == 1'b0);
      @(posedge drv_if.clk);
      wait (drv_if.rst_n == 1'b1);
      @(posedge drv_if.clk);
      drv_if.rx_ready <= 1'b1;
      phase.drop_objection(this);
    endtask : reset_phase

    virtual task main_phase(uvm_phase phase);
      drv_if.rx_ready <= 1'b1;
      forever begin
        comm_link_seq_item tr;
        seq_item_port.get_next_item(tr);

        // Optional idle cycles between transfers
        repeat (tr.idle_cycles) @(posedge drv_if.clk);

        // Drive transaction
        drv_if.tx_data  <= tr.data;
        drv_if.tx_valid <= 1'b1;
        do @(posedge drv_if.clk); while (!drv_if.tx_ready);
        drv_if.tx_valid <= 1'b0;

        seq_item_port.item_done();
      end
    endtask : main_phase
  endclass : comm_link_driver

  // ---------------------------------------------------------------------------
  // Monitor
  // ---------------------------------------------------------------------------
  class comm_link_monitor extends uvm_component;
    `uvm_component_utils(comm_link_monitor)

    virtual comm_link_if mon_if;
    uvm_analysis_port #(comm_link_seq_item) tx_ap;
    uvm_analysis_port #(comm_link_seq_item) rx_ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      tx_ap = new("tx_ap", this);
      rx_ap = new("rx_ap", this);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual comm_link_if)::get(this, "", "vif", mon_if)) begin
        `uvm_fatal(get_type_name(), "Virtual interface not found for monitor")
      end
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
      forever begin
        @(posedge mon_if.clk);
        if (mon_if.tx_valid && mon_if.tx_ready) begin
          comm_link_seq_item tx_tr = comm_link_seq_item::type_id::create("tx_tr");
          tx_tr.data = mon_if.tx_data;
          tx_tr.idle_cycles = 0;
          tx_ap.write(tx_tr);
        end

        if (mon_if.rx_valid && mon_if.rx_ready) begin
          comm_link_seq_item rx_tr = comm_link_seq_item::type_id::create("rx_tr");
          rx_tr.data = mon_if.rx_data;
          rx_tr.idle_cycles = 0;
          rx_ap.write(rx_tr);
        end
      end
    endtask : run_phase
  endclass : comm_link_monitor

  // ---------------------------------------------------------------------------
  // Agent
  // ---------------------------------------------------------------------------
  class comm_link_agent extends uvm_component;
    `uvm_component_utils(comm_link_agent)

    uvm_active_passive_enum is_active = UVM_ACTIVE;
    comm_link_sequencer  sequencer;
    comm_link_driver     driver;
    comm_link_monitor    monitor;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      void'(uvm_config_db#(uvm_active_passive_enum)::get(this, "", "is_active", is_active));

      monitor = comm_link_monitor::type_id::create("monitor", this);

      if (is_active == UVM_ACTIVE) begin
        sequencer = comm_link_sequencer::type_id::create("sequencer", this);
        driver    = comm_link_driver::type_id::create("driver", this);
      end
    endfunction : build_phase

    virtual function void connect_phase(uvm_phase phase);
      if (is_active == UVM_ACTIVE) begin
        driver.seq_item_port.connect(sequencer.seq_item_export);
      end
    endfunction : connect_phase
  endclass : comm_link_agent

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  class comm_link_scoreboard extends uvm_component;
    `uvm_component_utils(comm_link_scoreboard)

    uvm_analysis_export #(comm_link_seq_item) tx_export;
    uvm_analysis_export #(comm_link_seq_item) rx_export;

    protected uvm_tlm_analysis_fifo #(comm_link_seq_item) tx_fifo;
    protected uvm_tlm_analysis_fifo #(comm_link_seq_item) rx_fifo;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      tx_export = new("tx_export", this);
      rx_export = new("rx_export", this);
      tx_fifo = new("tx_fifo", this);
      rx_fifo = new("rx_fifo", this);
    endfunction : new

    virtual function void connect_phase(uvm_phase phase);
      tx_export.connect(tx_fifo.analysis_export);
      rx_export.connect(rx_fifo.analysis_export);
    endfunction : connect_phase

    virtual task run_phase(uvm_phase phase);
      forever begin
        comm_link_seq_item tx_tr;
        comm_link_seq_item rx_tr;
        tx_fifo.get(tx_tr);
        rx_fifo.get(rx_tr);

        if (tx_tr.data !== rx_tr.data) begin
          `uvm_error(get_type_name(), $sformatf("Data mismatch. Expected %0h, got %0h", tx_tr.data, rx_tr.data))
        end else begin
          `uvm_info(get_type_name(), $sformatf("Matched transfer %0h", tx_tr.data), UVM_MEDIUM)
        end
      end
    endtask : run_phase
  endclass : comm_link_scoreboard

  // ---------------------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------------------
  class comm_link_env extends uvm_env;
    `uvm_component_utils(comm_link_env)

    comm_link_agent      agent;
    comm_link_scoreboard scoreboard;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = comm_link_agent::type_id::create("agent", this);
      scoreboard = comm_link_scoreboard::type_id::create("scoreboard", this);
    endfunction : build_phase

    virtual function void connect_phase(uvm_phase phase);
      agent.monitor.tx_ap.connect(scoreboard.tx_export);
      agent.monitor.rx_ap.connect(scoreboard.rx_export);
    endfunction : connect_phase
  endclass : comm_link_env

  // ---------------------------------------------------------------------------
  // Test
  // ---------------------------------------------------------------------------
  class comm_link_test extends uvm_test;
    `uvm_component_utils(comm_link_test)

    comm_link_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction : new

    virtual function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = comm_link_env::type_id::create("env", this);
    endfunction : build_phase

    virtual task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      comm_link_sequence seq = comm_link_sequence::type_id::create("seq");
      if (!seq.randomize()) begin
        `uvm_fatal(get_type_name(), "Sequence randomization failed")
      end
      seq.start(env.agent.sequencer);
      phase.drop_objection(this);
    endtask : run_phase
  endclass : comm_link_test

endpackage : comm_link_pkg

`endif // COMM_LINK_PKG_SV
