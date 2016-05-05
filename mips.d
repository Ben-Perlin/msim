import std.exception;
import std.format;

private {
uint bitSlice(uint value, uint high, uint low) pure
in {
    assert(high < 32);
    assert(high >= low);
}
body {
    return (value & (-1 >>> (31-high))) >> low;
}
}

/// MIPS simulator class
class MIPS
{
private:
    enum Opcode: uint {R  = 0x00, addi = 0x8, andi = 0xc, ori = 0x0d, beq = 0x4,
                       bne = 0x5, lw = 0x23, sw = 0x2b, j = 0x2, jal = 0x3}

    enum Funct: uint {add = 0x20, sub = 0x22, and = 0x24, or = 0x25, nor = 0x27,
                      slt = 0x2a, sll = 0x00, srl = 0x02, jr = 0x8}

    enum ALUopcode: uint {none, switchFunct, add, sub, and, or, nor, slt, sll, srl, passA}

    class ControlUnit
    {
    private:
        enum State {start, fetch, decode, RformatExecute, RformatWrite,
                    JR, IformatArith, IformatWrite, branchEQ, branchNE, jump,
                    lw1, lw2, lw3, sw1, sw2, jal1, jal2}

        State state_, nextState;

        State decodeRformat() const {
            with (State)
            switch (funct) with (Funct) {
            case add, sub, and, or, nor, slt, sll, srl: return RformatExecute;
            case jr: return JR;
            default:
                throw new Exception(format("Error at [0x%08Xa]: illegal funct %06b", PC.contents, funct));
            }

            assert(0);
        }

        State decodeInstruction() const {
            with (State)
            switch (opcode) with (Opcode) {
            case R: return decodeRformat();
            case addi, andi, ori: return IformatArith;
            case beq: return branchEQ;
            case bne: return branchNE;
            case j: return jump;
            case jal: return jal1;
            case lw: return lw1;
            case sw: return sw1;
            default:
                throw new Exception(format("Error at [0x%08X]: illegal opcode %06b", PC.contents, opcode));
            }

            assert(0);
        }

        State nextStateLogic() const {
            final switch (state) with (State) {
            case start: return fetch;
            case fetch: return decode;
            case decode: return decodeInstruction();
            case RformatExecute: return RformatWrite;
            case RformatWrite: return fetch;
            case JR: return fetch;
            case IformatArith: return IformatWrite;
            case IformatWrite: return fetch;
            case branchEQ: return fetch;
            case branchNE: return fetch;
            case jump: return fetch;
            case jal1: return jal2;
            case jal2: return fetch;
            case lw1: return lw2;
            case lw2: return lw3;
            case lw3: return fetch;
            case sw1: return sw2;
            case sw2: return fetch;
            }

            assert(0);
        }

        static struct Signals
        {
            bool PCWrite;
            bool PCWriteCond;
            bool PCWriteCondNEQ;
            uint PCsource;
            bool IorD;
            bool MemRead;
            bool MemWrite;
            bool MemToReg;
            bool IRwrite;
            uint RegDest;
            bool RegWrite;
            bool ALUsrcA;
            uint ALUsrcB;
            ALUopcode ALUmasterOp;
        }
        Signals signals_;

        // decode ALUcontrolOp for addi, andi, ori
        // depends on stability of opcode when called (safe)
        ALUopcode IformatALU() const {
            with (ALUopcode)
            switch (opcode) with (Opcode) {
            case addi: return add;
            case andi: return and;
            case ori:  return or;
            default: assert(0);
            }
        }

        void outputLogic()
          out {
             with (signals_) {
                  assert(!IRwrite || MemRead);
                  assert(!PCWriteCondNEQ || PCWriteCond);
                  assert(!(MemRead && MemWrite));
             }
          }
          body {
            signals_ = Signals.init; // set default value of 0 for all signals

            with (signals_)
            with (ALUopcode)
            final switch (state_) with (State) {
            case start: break;

            case fetch:
                PCWrite = MemRead = IRwrite = ALUsrcB = 1;
                ALUmasterOp = add;
                break;

            case decode:
                ALUsrcB = 3;
                ALUmasterOp = add;
                break;

            case RformatExecute:
                ALUsrcA = 1;
                ALUmasterOp = switchFunct;
                break;

            case RformatWrite:
                RegDest = 1;
                RegWrite = 1;
                break;

            case JR:
                PCWrite = 1;
                ALUsrcA = 1;
                ALUmasterOp = passA;
                break;

            case IformatArith:
                ALUsrcA = 1;
                ALUsrcB = 2;
                ALUmasterOp = IformatALU();
                break;

            case IformatWrite:
                RegWrite = 1;
                break;

            case branchEQ:
                PCWriteCond = 1;
                ALUsrcA = 1;
                PCsource = 1;
                ALUmasterOp = sub;
                break;

            case branchNE:
                PCWriteCond = PCWriteCondNEQ = 1;
                ALUsrcA = 1;
                PCsource = 1;
                ALUmasterOp = sub;
                break;

            case jump:
                PCWrite = 1;
                PCsource = 2;
                break;

            case jal1:
                ALUmasterOp = passA;
                break;

            case jal2:
                PCWrite = RegWrite = 1;
                RegDest = PCsource = 2;
                break;

            case lw1, sw1:
                ALUsrcA = 1;
                ALUsrcB = 2;
                ALUmasterOp = add;
                break;

            case lw2:
                IorD = MemRead = 1;
                break;

            case lw3:
                RegWrite = MemToReg = 1;
                break;

            case sw2:
                IorD = MemWrite = 1;
                break;
            }
        }

    public:
        void beginStrobe() {
            nextState = nextStateLogic();
        }

        void finishStrobe() {
            state_ = nextState;
            outputLogic();  // update output signals
        }

        auto opDispatch(string name)() const @property {
            mixin(q{return signals_.} ~ name ~ ";");
        }

        State state() const @property {return state_;}
    }

    class RegisterBase {
    private:
        uint master;
        uint slave;

    public:
        // void beginStrobe(); // does not need to be made virtual here
        void finishStrobe() {slave = master;}

        override string toString() const @property {return format("0x%08X", slave);}

        uint opAssign(uint rhs) {return (slave = master = rhs);}
        uint contents() const @property {return slave;}
    }

    /// use mixins and overloading to wire the register
    class Register(string input, string enable = "true") : RegisterBase
    {
        void beginStrobe() {mixin("if (" ~ enable ~ ") master = " ~ input ~ ";");}
        alias contents this;
    }

    class Memory
    {
        uint[uint] store;
        bool dirty;
        uint dirtyAddress, dirtyData;

        uint read() {
            dirtyAddress = muxIorD;
            enforce(!(dirtyAddress&3), format("Error in memory.read: address not word aligned [0x08X]", dirtyAddress));

            uint *p = (dirtyAddress in store);
            if (p is null) {
                dirty = true;
                return (store[dirtyAddress] = dirtyData = 0);
            }

            return *p;
        }

        void strobe()
        in {
            assert(!(control.MemWrite && control.MemRead));
        } body {
            dirty = false;
            if (!control.MemWrite) return;
            dirtyAddress = muxIorD;
            enforce(!(dirtyAddress&3), format("Error in memory.strobe: address not word aligned [0x08X]", dirtyAddress));

            dirty = true;
            store[dirtyAddress] = dirtyData = B;
        }
    }

    class RegisterFile {
    private:
        bool write;
        uint index;
        uint data;

    public:
        uint[32] registers;
        uint ReadData1() @property {return registers[rs];}
        uint ReadData2() @property {return registers[rt];}

        void beginStrobe() {
            index = muxWriteAddr;
            write = control.RegWrite && index;
            if (write) data = muxWriteData;
        }

        void finishStrobe() {if (write) registers[index] = data;}
    }

public:
    size_t time;

    // functional units
    ControlUnit control;
    RegisterFile regFile;
    Memory memory;

    Register!("memory.read", "control.IRwrite") IR;
    Register!("memory.read", "control.MemRead") MDR;
    Register!("regFile.ReadData1") A;
    Register!("regFile.ReadData2") B;
    Register!("alu") ALUout;
    Register!("muxPCsrc", "PCWrite") PC;

    bool finished() {return (PC.contents == exitPoint)
                         && (control.state == ControlUnit.State.fetch);};

    uint opcode() const {return IR.bitSlice(31, 26);}
    uint rs() const {return IR.bitSlice(25, 21);}
    uint rt() const {return IR.bitSlice(20, 16);}
    uint rd() const {return IR.bitSlice(15, 11);}
    uint shamt() const {return IR.bitSlice(10, 6);}
    uint funct() const {return IR.bitSlice(5, 0);}
    uint immediate() const {return IR.bitSlice(15, 0);}
    uint address() const {return IR.bitSlice(25, 0);}

    uint SEXedImmediate() const {return cast(uint) ((cast(int) (immediate << 16)) >> 16);}
    uint scaledOffset() const {return SEXedImmediate << 2;}
    uint jumpAddress() const {return ((PC & 0xF000_0000) | (address << 2));}

    ALUopcode aluControl() const {
        if (control.ALUmasterOp != ALUopcode.switchFunct) return control.ALUmasterOp;

        switch (funct) with (Funct) {
        case add: return ALUopcode.add;
        case sub: return ALUopcode.sub;
        case and: return ALUopcode.and;
        case or:  return ALUopcode.or;
        case nor: return ALUopcode.nor;
        case slt: return ALUopcode.slt;
        case sll: return ALUopcode.sll;
        case srl: return ALUopcode.srl;
        default: assert (0);
        }
    }

    uint alu() const {
        final switch (aluControl) with (ALUopcode) {
        case none: return 0;
        case switchFunct: assert(0);
        case add: return (muxALUsrcA + muxALUsrcB);
        case sub: return (muxALUsrcA - muxALUsrcB);
        case and: return (muxALUsrcA & muxALUsrcB);
        case or: return  (muxALUsrcA | muxALUsrcB);
        case nor: return ~(muxALUsrcA | muxALUsrcB);
        case slt: return (cast(int) muxALUsrcA < cast(int) muxALUsrcB) ? 1 : 0;
        case sll: return (muxALUsrcB << shamt);
        case srl: return (muxALUsrcB >> shamt);
        case passA: return muxALUsrcA;
        }
    }

    bool zero() const {return alu() == 0;}

    bool PCWrite() const {return control.PCWrite
        || (control.PCWriteCond && (zero ^ control.PCWriteCondNEQ));}

    uint muxIorD() const {return (control.IorD) ? ALUout.contents : PC.contents;}

    uint muxWriteAddr() const {
        switch (control.RegDest()) {
        case 0: return rt;
        case 1: return rd;
        case 2: return 31u;
        default: assert(0);
        }
    };

    uint muxWriteData() const {return control.MemToReg ? MDR.contents : ALUout.contents;}

    uint muxALUsrcA() const {return control.ALUsrcA ? A.contents : PC.contents;}

    uint muxALUsrcB() const {
        switch (control.ALUsrcB()) {
        case 0: return B;
        case 1: return 4;
        case 2: return SEXedImmediate;
        case 3: return scaledOffset;
        default: assert(0);
        }
    }

    uint muxPCsrc() const {
        switch (control.PCsource()) {
        case 0: return alu;
        case 1: return ALUout;
        case 2: return jumpAddress;
        default: assert(0);
        }
    }

    uint exitPoint; // address that halts machine when read into IR

    /// allocate nested classes with appropriate context
    this() {
        control = this.new ControlUnit();
        regFile = this.new RegisterFile();
        memory = this.new Memory();

        PC = this.new typeof(PC);
        IR = this.new typeof(IR);
        MDR = this.new typeof(MDR);
        A = this.new typeof(A);
        B = this.new typeof(B);
        ALUout = this.new typeof(ALUout);
    }

    void step() {
        memory.strobe(); // strobed first so that auto initialization prints correctly

        // calculate values for non-blocking assignments
        control.beginStrobe();
        IR.beginStrobe();
        MDR.beginStrobe();
        A.beginStrobe();
        B.beginStrobe();
        ALUout.beginStrobe();
        PC.beginStrobe();
        regFile.beginStrobe();

        // assign new values
        control.finishStrobe();
        IR.finishStrobe();
        MDR.finishStrobe();
        A.finishStrobe();
        B.finishStrobe();
        ALUout.finishStrobe();
        PC.finishStrobe();
        regFile.finishStrobe();

        time++;
    }
}
