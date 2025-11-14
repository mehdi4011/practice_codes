int calc(int bot, int top) {
    if (bot > top) return 0;
    bot = (bot + 1) & ~1;
    top = top & ~1;
    if (bot > top) return 0;
    return (((top -bot) >> 1) + 1) * (bot + top) / 2;
}
int main() {
    calc(1, 5);
}