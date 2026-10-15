// SPDX-License-Identifier: Apache-2.0
// apb_uart — APB UART，8N1，TX + RX（单字节保持寄存器）
//
// 寄存器（PADDR[7:0]）：
//   0x00 TXDATA   W   写一字节进发送器（busy 时写入被丢弃，固件应先查 STATUS.tx_busy）
//   0x04 STATUS   R   bit0 tx_busy  bit1 rx_valid  bit2 rx_overrun  bit3 rx_frame_err
//   0x08 PRESCALE R/W 位周期 = PRESCALE+1 个 PCLK（TX/RX 共用）
//   0x0C RXDATA   R   读出接收字节并清 rx_valid
//   0x10 IE       R/W bit0 rx_valid 中断使能
//   0x14 ERRCLR   W1C bit2 清 overrun  bit3 清 frame_err
//
// RX：两级同步 → 下降沿检测 → 半位后确认起始位 → 每位中点采样 → 停止位为 0 记帧错误（丢弃该字节）。

module apb_uart (
  input  logic        PCLK,
  input  logic        PRESETn,
  input  logic        PSEL,
  input  logic        PENABLE,
  input  logic        PWRITE,
  input  logic [31:0] PADDR,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  output logic        PREADY,
  output logic        tx_o,
  input  logic        rx_i,
  output logic        irq_o,
  output logic        busy_o         // 收或发进行中（PMU 据此禁止深睡关钟）
);

  logic [15:0] pr_q;

  // ---------------- TX ----------------
  logic [15:0] tcnt_q;
  logic [3:0]  tpos_q;
  logic [9:0]  tsh_q;
  logic        tbusy_q, tx_q;

  // ---------------- RX ----------------
  logic [1:0]  rx_s;
  logic        rx_prev;
  logic        rbusy_q;
  logic [15:0] rcnt_q;
  logic [3:0]  rpos_q;           // 0=起始位确认，1..8=数据位，9=停止位
  logic [7:0]  rsh_q, rdata_q;
  logic        rvalid_q, rovr_q, rfe_q, ie_q;

  assign PREADY = 1'b1;
  assign tx_o   = tbusy_q ? tx_q : 1'b1;
  assign irq_o  = ie_q & rvalid_q;
  assign busy_o = tbusy_q | rbusy_q;

  wire wr_en   = PSEL && PENABLE && PWRITE;
  wire rd_pop  = PSEL && PENABLE && !PWRITE && (PADDR[7:0] == 8'h0C);
  wire tx_load = wr_en && (PADDR[7:0] == 8'h00) && !tbusy_q;

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      pr_q <= 16'd8; ie_q <= 1'b0;
    end else if (wr_en) begin
      if (PADDR[7:0] == 8'h08) pr_q <= PWDATA[15:0];
      if (PADDR[7:0] == 8'h10) ie_q <= PWDATA[0];
    end
  end

  // TX 引擎
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      tbusy_q <= 1'b0; tpos_q <= '0; tcnt_q <= '0; tsh_q <= 10'h3FF; tx_q <= 1'b1;
    end else if (tx_load) begin
      tbusy_q <= 1'b1;
      tsh_q   <= {1'b1, PWDATA[7:0], 1'b0};
      tpos_q  <= 4'd1;
      tcnt_q  <= '0;
      tx_q    <= 1'b0;
    end else if (tbusy_q) begin
      if (tcnt_q == pr_q) begin
        tcnt_q <= '0;
        if (tpos_q == 4'd10) begin
          tbusy_q <= 1'b0; tx_q <= 1'b1;
        end else begin
          tpos_q <= tpos_q + 4'd1;
          tx_q   <= tsh_q[tpos_q];
        end
      end else tcnt_q <= tcnt_q + 16'd1;
    end
  end

  // RX 引擎
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      rx_s <= 2'b11; rx_prev <= 1'b1; rbusy_q <= 1'b0; rcnt_q <= '0; rpos_q <= '0;
      rsh_q <= '0; rdata_q <= '0; rvalid_q <= 1'b0; rovr_q <= 1'b0; rfe_q <= 1'b0;
    end else begin
      rx_s    <= {rx_s[0], rx_i};
      rx_prev <= rx_s[1];
      if (rd_pop) rvalid_q <= 1'b0;
      if (wr_en && PADDR[7:0] == 8'h14) begin
        if (PWDATA[2]) rovr_q <= 1'b0;
        if (PWDATA[3]) rfe_q  <= 1'b0;
      end

      if (!rbusy_q) begin
        if (rx_prev && !rx_s[1]) begin          // 起始位下降沿
          rbusy_q <= 1'b1; rpos_q <= 4'd0; rcnt_q <= {1'b0, pr_q[15:1]};  // 半位
        end
      end else if (rcnt_q != 16'd0) begin
        rcnt_q <= rcnt_q - 16'd1;
      end else begin
        rcnt_q <= pr_q;
        if (rpos_q == 4'd0) begin
          if (rx_s[1]) rbusy_q <= 1'b0;          // 毛刺：不是有效起始位
          else rpos_q <= 4'd1;
        end else if (rpos_q <= 4'd8) begin
          rsh_q  <= {rx_s[1], rsh_q[7:1]};       // LSB 先
          rpos_q <= rpos_q + 4'd1;
        end else begin                           // 停止位
          rbusy_q <= 1'b0;
          if (!rx_s[1]) rfe_q <= 1'b1;
          else begin
            if (rvalid_q && !rd_pop) rovr_q <= 1'b1;
            rdata_q  <= rsh_q;
            rvalid_q <= 1'b1;
          end
        end
      end
    end
  end

  always_comb begin
    unique case (PADDR[7:0])
      8'h04:   PRDATA = {28'b0, rfe_q, rovr_q, rvalid_q, tbusy_q};
      8'h08:   PRDATA = {16'b0, pr_q};
      8'h0C:   PRDATA = {24'b0, rdata_q};
      8'h10:   PRDATA = {31'b0, ie_q};
      default: PRDATA = 32'b0;
    endcase
  end

endmodule
