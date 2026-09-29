#!/usr/bin/env python3
"""rv32i_tools.py - tiny RV32I assembler + instruction-set simulator (ISS).

Used to generate the hex programs in this project and an independent
"golden" expected result for the core-instruction test:
  * Asm  : builds programs, resolves labels, emits $readmemh hex
  * Iss  : executes the assembled words per the RV32I spec (no RTL involved)
"""
M32 = 0xFFFFFFFF
def s32(v):  v &= M32; return v - (1 << 32) if v & 0x80000000 else v

# ---- encoders ---------------------------------------------------------
def _r(f7, rs2, rs1, f3, rd, op): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def _i(imm, rs1, f3, rd, op):     return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def _s(imm, rs2, rs1, f3, op):    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op
def _b(off, rs2, rs1, f3):
    return (((off >> 12) & 1) << 31) | (((off >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
           (((off >> 1) & 0xF) << 8) | (((off >> 11) & 1) << 7) | 0x63
def _u(imm20, rd, op):            return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | op
def _j(off, rd):
    return (((off >> 20) & 1) << 31) | (((off >> 1) & 0x3FF) << 21) | (((off >> 11) & 1) << 20) | \
           (((off >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F

R_OPS = {'add': (0, 0), 'sub': (0x20, 0), 'sll': (0, 1), 'slt': (0, 2), 'sltu': (0, 3),
         'xor': (0, 4), 'srl': (0, 5), 'sra': (0x20, 5), 'or': (0, 6), 'and': (0, 7)}
I_OPS = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
SH_OPS = {'slli': (0, 1), 'srli': (0, 5), 'srai': (0x20, 5)}
LD_OPS = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
ST_OPS = {'sb': 0, 'sh': 1, 'sw': 2}
BR_OPS = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}


class Asm:
    def __init__(self):
        self.items = []      # (kind, args, text)
        self.labels = {}
        self.n = 0           # instruction count (word index)

    def _add(self, kind, args, text):
        self.items.append((kind, args, text)); self.n += 1

    def label(self, name):
        assert name not in self.labels, name
        self.labels[name] = self.n * 4

    # ---- instructions ----
    def __getattr__(self, name):
        if name in R_OPS:
            return lambda rd, rs1, rs2: self._add('R', (name, rd, rs1, rs2), f"{name} x{rd}, x{rs1}, x{rs2}")
        if name in I_OPS:
            return lambda rd, rs1, imm: self._add('I', (name, rd, rs1, imm), f"{name} x{rd}, x{rs1}, {imm}")
        if name in SH_OPS:
            return lambda rd, rs1, sh: self._add('SH', (name, rd, rs1, sh), f"{name} x{rd}, x{rs1}, {sh}")
        if name in LD_OPS:
            return lambda rd, rs1, off: self._add('LD', (name, rd, rs1, off), f"{name} x{rd}, {off}(x{rs1})")
        if name in ST_OPS:
            return lambda rs2, rs1, off: self._add('ST', (name, rs2, rs1, off), f"{name} x{rs2}, {off}(x{rs1})")
        if name in BR_OPS:
            return lambda rs1, rs2, lbl: self._add('B', (name, rs1, rs2, lbl), f"{name} x{rs1}, x{rs2}, {lbl}")
        raise AttributeError(name)

    def lui(self, rd, imm20):   self._add('U', ('lui', rd, imm20), f"lui x{rd}, 0x{imm20 & 0xFFFFF:X}")
    def auipc(self, rd, imm20): self._add('U', ('auipc', rd, imm20), f"auipc x{rd}, 0x{imm20 & 0xFFFFF:X}")
    def jal(self, rd, lbl):     self._add('J', (rd, lbl), f"jal x{rd}, {lbl}")
    def jalr(self, rd, rs1, off): self._add('JR', (rd, rs1, off), f"jalr x{rd}, {off}(x{rs1})")
    def fence(self):            self._add('F', (), "fence")
    def nop(self):              self.addi(0, 0, 0)

    def li(self, rd, imm):
        imm &= M32
        v = s32(imm)
        if -2048 <= v < 2048:
            self.addi(rd, 0, v)
        else:
            lo = s32(imm) & 0xFFF
            if lo >= 0x800: lo -= 0x1000
            hi = ((imm - lo) >> 12) & 0xFFFFF
            self.lui(rd, hi)
            if lo: self.addi(rd, rd, lo)

    # ---- assemble ----
    def assemble(self):
        words = []
        for idx, (kind, a, _t) in enumerate(self.items):
            pc = idx * 4
            if kind == 'R':
                n, rd, rs1, rs2 = a; f7, f3 = R_OPS[n]; w = _r(f7, rs2, rs1, f3, rd, 0x33)
            elif kind == 'I':
                n, rd, rs1, imm = a; w = _i(imm, rs1, I_OPS[n], rd, 0x13)
            elif kind == 'SH':
                n, rd, rs1, sh = a; f7, f3 = SH_OPS[n]; w = _r(f7, sh, rs1, f3, rd, 0x13)
            elif kind == 'LD':
                n, rd, rs1, off = a; w = _i(off, rs1, LD_OPS[n], rd, 0x03)
            elif kind == 'ST':
                n, rs2, rs1, off = a; w = _s(off, rs2, rs1, ST_OPS[n], 0x23)
            elif kind == 'B':
                n, rs1, rs2, lbl = a; w = _b(self.labels[lbl] - pc, rs2, rs1, BR_OPS[n])
            elif kind == 'U':
                n, rd, imm = a; w = _u(imm, rd, 0x37 if n == 'lui' else 0x17)
            elif kind == 'J':
                rd, lbl = a; w = _j(self.labels[lbl] - pc, rd)
            elif kind == 'JR':
                rd, rs1, off = a; w = _i(off, rs1, 0, rd, 0x67)
            elif kind == 'F':
                w = 0x0FF0000F
            words.append(w & M32)
        return words

    def hex_lines(self, header=""):
        words = self.assemble()
        inv = {v: k for k, v in self.labels.items()}
        out = [header.rstrip("\n")] if header else []
        for i, w in enumerate(words):
            tag = (f"{inv[i*4]}: " if i * 4 in inv else "")
            out.append(f"{w:08X}  // 0x{i*4:03X}  {tag}{self.items[i][2]}")
        return "\n".join(out) + "\n", words


# ---- Instruction-set simulator ---------------------------------------
class Iss:
    """Executes assembled words per the RV32I spec. Only DMEM (0x1000_0000) is modelled."""
    DMEM = 0x10000000
    def __init__(self, words):
        self.imem = words; self.x = [0] * 32; self.pc = 0; self.mem = {}   # byte-addressed

    def _ld(self, addr, n, signed):
        v = 0
        for i in range(n): v |= self.mem.get(addr + i, 0) << (8 * i)
        if signed and v & (1 << (8 * n - 1)): v -= 1 << (8 * n)
        return v & M32
    def _st(self, addr, n, val):
        for i in range(n): self.mem[addr + i] = (val >> (8 * i)) & 0xFF

    def run(self, max_steps=200000):
        for _ in range(max_steps):
            w = self.imem[self.pc // 4]; op = w & 0x7F
            rd = (w >> 7) & 31; f3 = (w >> 12) & 7; rs1 = (w >> 15) & 31; rs2 = (w >> 20) & 31; f7 = w >> 25
            a, b = self.x[rs1], self.x[rs2]; npc = self.pc + 4; wr = None
            immi = s32(w) >> 20
            if op == 0x33:
                sh = b & 31
                wr = {(0,0): a+b, (0x20,0): a-b, (0,1): a << sh, (0,2): int(s32(a) < s32(b)), (0,3): int(a < b),
                      (0,4): a ^ b, (0,5): a >> sh, (0x20,5): s32(a) >> sh, (0,6): a | b, (0,7): a & b}[(f7, f3)]
            elif op == 0x13:
                sh = rs2
                wr = {0: a+immi, 2: int(s32(a) < immi), 3: int(a < (immi & M32)), 4: a ^ immi, 6: a | immi, 7: a & immi}.get(f3)
                if f3 == 1: wr = a << sh
                if f3 == 5: wr = (s32(a) >> sh) if f7 == 0x20 else (a >> sh)
            elif op == 0x03:
                ad = (a + immi) & M32
                wr = {0: self._ld(ad,1,True), 1: self._ld(ad,2,True), 2: self._ld(ad,4,False),
                      4: self._ld(ad,1,False), 5: self._ld(ad,2,False)}[f3]
            elif op == 0x23:
                imms = s32(((f7 << 5) | rd) << 20) >> 20
                self._st((a + imms) & M32, {0:1, 1:2, 2:4}[f3], b)
            elif op == 0x63:
                immb = s32((((w>>31)&1)<<12 | ((w>>7)&1)<<11 | ((w>>25)&0x3F)<<5 | ((w>>8)&0xF)<<1) << 19) >> 19
                t = {0: a == b, 1: a != b, 4: s32(a) < s32(b), 5: s32(a) >= s32(b), 6: a < b, 7: a >= b}[f3]
                if t: npc = (self.pc + immb) & M32
            elif op == 0x37: wr = w & 0xFFFFF000
            elif op == 0x17: wr = self.pc + (w & 0xFFFFF000)
            elif op == 0x6F:
                immj_raw = (((w>>31)&1)<<20) | (((w>>12)&0xFF)<<12) | (((w>>20)&1)<<11) | (((w>>21)&0x3FF)<<1)
                immj = s32(immj_raw << 11) >> 11
                wr = self.pc + 4; npc = (self.pc + immj) & M32
            elif op == 0x67:
                wr = self.pc + 4; npc = ((a + immi) & M32) & ~1
            elif op == 0x0F: pass
            else: raise RuntimeError(f"unsupported opcode {op:#x} at pc={self.pc:#x}")
            if wr is not None and rd != 0: self.x[rd] = wr & M32
            if npc == self.pc: return            # jal x0,0 -> halt
            self.pc = npc
        raise RuntimeError("ISS did not halt")

    def dmem_word(self, idx): return self._ld(self.DMEM + 4 * idx, 4, False)
