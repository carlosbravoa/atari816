// Provenance: the 65C816 CPU core of SNES_FPGA by Sergiy Dvodnenko (srg320), with changes
// by gyurco and nand2mario, as distributed in nand2mario's SNESTang
// (https://github.com/nand2mario/snestang), which is under the GPL-3.0. See core/LICENSE.

module adder4(A, B, CI, S, CO);
   input [3:0]  A;
   input [3:0]  B;
   input        CI;
   output [3:0] S;
   output       CO;


   wire         CO0;
   wire         CO1;
   wire         CO2;


   bit_adder b_add0(A[0], B[0], CI, S[0], CO0);

   bit_adder b_add1(A[1], B[1], CO0, S[1], CO1);

   bit_adder b_add2(A[2], B[2], CO1, S[2], CO2);

   bit_adder b_add3(A[3], B[3], CO2, S[3], CO);

endmodule
