/* a function that no file defines: hcc says its C name */
// HCC: -o X.PRG
// EXPECT-HCC: undefined: fire_laser (used in
int fire_laser(int power);
int main(void) { return fire_laser(3); }
