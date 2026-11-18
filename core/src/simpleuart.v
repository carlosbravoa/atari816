/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Claire Xenia Wolf <claire@yosyshq.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

module simpleuart #(parameter integer DEFAULT_DIV = 1) (
	input clk,
	input resetn,

	output ser_tx,
	input  ser_rx,

	input   [3:0] reg_div_we,
	input  [31:0] reg_div_di,
	output [31:0] reg_div_do,

	input         reg_dat_we,
	input         reg_dat_re,
	input  [31:0] reg_dat_di,
	output [31:0] reg_dat_do,
	output        reg_dat_wait
);
	reg [15:0] cfg_divider /* synthesis syn_keep=1 */;

	reg [3:0] recv_state;
	reg [15:0] recv_divcnt;
	reg [7:0] recv_pattern;
	// 64-byte receive FIFO: the firmware main loop is slower than one byte time
	// (87 us), so a single-byte buffer dropped most of every CH9350 mouse frame.
	reg [7:0] rx_fifo [0:63];
	reg [5:0] rx_wp, rx_rp;
	reg       rx_re_d;
	wire      rx_have = rx_wp != rx_rp;
	wire [7:0] rx_head = rx_fifo[rx_rp];

	reg [9:0] send_pattern;
	reg [3:0] send_bitcnt;
	reg [15:0] send_divcnt;
	reg send_dummy;

	assign reg_div_do = cfg_divider;

	assign reg_dat_wait = reg_dat_we && (send_bitcnt != 0 || send_dummy);
	assign reg_dat_do = rx_have ? {24'b0, rx_head} : ~0;

	always @(posedge clk) begin
		if (!resetn) begin
			cfg_divider <= DEFAULT_DIV;
		end else begin
			if (reg_div_we[0]) cfg_divider[ 7: 0] <= reg_div_di[ 7: 0];
			if (reg_div_we[1]) cfg_divider[15: 8] <= reg_div_di[15: 8];
			// if (reg_div_we[2]) cfg_divider[23:16] <= reg_div_di[23:16];
			// if (reg_div_we[3]) cfg_divider[31:24] <= reg_div_di[31:24];
		end
	end

	always @(posedge clk) begin
		if (!resetn) begin
			recv_state <= 0;
			recv_divcnt <= 0;
			recv_pattern <= 0;
			rx_wp <= 0;
			rx_rp <= 0;
			rx_re_d <= 0;
		end else begin
			recv_divcnt <= recv_divcnt + 1;
			rx_re_d <= reg_dat_re;
			if (rx_re_d && !reg_dat_re && rx_have)      // pop when the read ends
				rx_rp <= rx_rp + 1'b1;
			case (recv_state)
				0: begin
					if (!ser_rx)
						recv_state <= 1;
					recv_divcnt <= 0;
				end
				1: begin
					if ({recv_divcnt, 1'b0} > cfg_divider) begin
						recv_state <= 2;
						recv_divcnt <= 0;
					end
				end
				10: begin
					if (recv_divcnt > cfg_divider) begin
						if (rx_wp + 6'd1 != rx_rp) begin         // full: drop the byte
							rx_fifo[rx_wp] <= recv_pattern;
							rx_wp <= rx_wp + 1'b1;
						end
						recv_state <= 0;
					end
				end
				default: begin
					if (recv_divcnt > cfg_divider) begin
						recv_pattern <= {ser_rx, recv_pattern[7:1]};
						recv_state <= recv_state + 1;
						recv_divcnt <= 0;
					end
				end
			endcase
		end
	end

	assign ser_tx = send_pattern[0];

	always @(posedge clk) begin
		if (reg_div_we[0])
			send_dummy <= 1;
		send_divcnt <= send_divcnt + 1;
		if (!resetn) begin
			send_pattern <= ~0;
			send_bitcnt <= 0;
			send_divcnt <= 0;
			send_dummy <= 1;
		end else begin
			if (send_dummy && send_bitcnt == 0) begin
				send_pattern <= ~0;
				send_bitcnt <= 15;
				send_divcnt <= 0;
				send_dummy <= 0;
			end else if (reg_dat_we && send_bitcnt == 0) begin
				send_pattern <= {1'b1, reg_dat_di[7:0], 1'b0};
				send_bitcnt <= 10;
				send_divcnt <= 0;
			end else if (send_divcnt > cfg_divider && send_bitcnt != 0) begin
				send_pattern <= {1'b1, send_pattern[9:1]};
				send_bitcnt <= send_bitcnt - 1;
				send_divcnt <= 0;
			end
		end
	end
endmodule
