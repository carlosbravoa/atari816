/* a flexible array member that is not last */
struct pkt {
    int n;
    char data[];        // EXPECT: error: flexible array member 'data' not at the end of the structure
    int crc;
};
int main(void) { return 0; }
