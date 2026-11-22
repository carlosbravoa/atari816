/* a definition that does not match its prototype */
int area(int w, int h);
long area(int w, int h) { return (long)w * h; }     // EXPECT: error: conflicting types for 'area'
int main(void) { return 0; }
