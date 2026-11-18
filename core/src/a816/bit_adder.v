// Provenance: the 65C816 CPU core of SNES_FPGA by Sergiy Dvodnenko (srg320), with changes
// by gyurco and nand2mario, as distributed in nand2mario's SNESTang
// (https://github.com/nand2mario/snestang), which is under the GPL-3.0. See core/LICENSE.

module bit_adder(A, B, CI, S, CO);
   input   A;
   input   B;
   input   CI;
   output  S;
   output  CO;
   assign S = ((~A) & (~B) & CI) | ((~A) & B & (~CI)) | (A & (~B) & (~CI)) | (A & B & CI);
   assign CO = ((~A) & B & CI) | (A & (~B) & CI) | (A & B & (~CI)) | (A & B & CI);

endmodule
