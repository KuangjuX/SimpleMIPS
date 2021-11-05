`include "defines.v"

module id_stage(
    input  wire                    cpu_rst_n,
    // 从取指阶段获得的PC值
    input  wire [`INST_ADDR_BUS]    id_pc_i,
    input  wire [`INST_ADDR_BUS]    id_pc_plus_4_i,

    // 从指令存储器读出的指令字
    input  wire [`INST_BUS     ]    id_inst_i,

    // 从通用寄存器堆读出的数据 
    input  wire [`REG_BUS      ]    rd1,
    input  wire [`REG_BUS      ]    rd2,

    // 从执行阶段获得的写回信号，用于做定向前推
    input wire                 exe2id_wreg_i,
    input wire [`REG_ADDR_BUS] exe2id_wa_i,
    input wire [`INST_BUS]     exe2id_wd_i,

    // 从访存阶段获得的写回信号，用于做定向前推
    input wire                 mem2id_wreg_i,
    input wire [`REG_ADDR_BUS] mem2id_wa_i,
    input wire [`INST_BUS]     mem2id_wd_i,
      
    // 送至执行阶段的译码信息
    output wire [`ALUTYPE_BUS  ]    id_alutype_o,
    output wire [`ALUOP_BUS    ]    id_aluop_o,
    output wire [`REG_ADDR_BUS ]    id_wa_o,
    output wire                     id_wreg_o,
    output wire                     id_whilo_o,
    output wire                     id_mreg_o,

    // 送至执行阶段的源操作数1、源操作数2
    output wire [`REG_BUS      ]    id_src1_o,
    output wire [`REG_BUS      ]    id_src2_o,
    output wire [`DATA_BUS     ]    id_din_o,
    //output wire [`REG_BUS      ]    id_retaddr_o,
      
    // 送至读通用寄存器堆端口的使能和地址
    output wire                     rreg1,
    output wire [`REG_ADDR_BUS ]    ra1,
    output wire                     rreg2,
    output wire [`REG_ADDR_BUS ]    ra2,

    output wire [`INST_ADDR_BUS]    jump_addr_1_o,
    output wire [`INST_ADDR_BUS]    jump_addr_2_o,
    output wire [`INST_ADDR_BUS]    jump_addr_3_o,
    output wire [`JTSEL_BUS]        jtsel_o,
    output wire [`INST_ADDR_BUS]    ret_addr_o
    );

    // 产生源操作数选择信号（源操作数可能来自执行与访存阶段，定向前推） 
    wire [1: 0] fwrd1 = (cpu_rst_n == `RST_ENABLE) ? 2'b00:
                        (exe2id_wreg_i == `WRITE_ENABLE && exe2id_wa_i == ra1 && rreg1 == `READ_ENABLE) ? 2'b01:
                        (mem2id_wreg_i == `WRITE_ENABLE && mem2id_wa_i == ra1 && rreg1 == `READ_ENABLE) ? 2'b10:
                        (rreg1 == `READ_ENABLE) ? 2'b11: 2'b00;

    wire [1: 0] fwrd2 = (cpu_rst_n == `RST_ENABLE) ? 2'b00:
                        (exe2id_wreg_i == `WRITE_ENABLE && exe2id_wa_i == ra2 && rreg2 == `READ_ENABLE) ? 2'b01:
                        (mem2id_wreg_i == `WRITE_ENABLE && mem2id_wa_i == ra2 && rreg2 == `READ_ENABLE) ? 2'b10:
                        (rreg1 == `READ_ENABLE) ? 2'b11: 2'b00;

    
    // 根据小端模式组织指令字
    wire [`INST_BUS] id_inst = {id_inst_i[7:0], id_inst_i[15:8], id_inst_i[23:16], id_inst_i[31:24]};

    // 提取指令字中各个字段的信息
    wire [5 :0] op   = id_inst[31:26];
    wire [5 :0] func = id_inst[5 : 0];
    wire [4 :0] rd   = id_inst[15:11];
    wire [4 :0] rs   = id_inst[25:21];
    wire [4 :0] rt   = id_inst[20:16];
    wire [4 :0] sa   = id_inst[10: 6];
    wire [15:0] imm  = id_inst[15: 0]; 


    /*-------------------- 第一级译码逻辑：确定当前需要译码的指令 --------------------*/
    wire inst_reg   = ~|op;
     // 暂不考虑J型指令 
    wire inst_imm   = ~inst_reg;

    // R-type 指令
    wire inst_add   = inst_reg& func[5]&~func[4]&~func[3]&~func[2]&~func[1]&~func[0];
    wire inst_addu  = inst_reg& func[5]&~func[4]&~func[3]&~func[2]&~func[1]& func[0];
    wire inst_sub   = inst_reg& func[5]&~func[4]&~func[3]&~func[2]& func[1]&~func[0];
    wire inst_subu  = inst_reg& func[5]&~func[4]&~func[3]&~func[2]& func[1]& func[0];
    wire inst_and   = inst_reg& func[5]&~func[4]&~func[3]& func[2]&~func[1]&~func[0];
    wire inst_slt   = inst_reg& func[5]&~func[4]& func[3]&~func[2]& func[1]&~func[0];
    wire inst_mult  = inst_reg&~func[5]& func[4]& func[3]&~func[2]&~func[1]&~func[0];
    wire inst_multu = inst_reg&~func[5]& func[4]& func[3]&~func[2]&~func[1]& func[0];
    wire inst_mfhi  = inst_reg&~func[5]& func[4]&~func[3]&~func[2]&~func[1]&~func[0];
    wire inst_mflo  = inst_reg&~func[5]& func[4]&~func[3]&~func[2]& func[1]&~func[0];
    wire inst_mthi  = inst_reg&~func[5]& func[4]&~func[3]&~func[2]&~func[1]& func[0];
    wire inst_mtlo  = inst_reg&~func[5]& func[4]&~func[3]&~func[2]& func[1]& func[0];
    wire inst_sll   = inst_reg&~func[5]&~func[4]&~func[3]&~func[2]&~func[1]&~func[0];
    wire inst_or    = inst_reg& func[5]&~func[4]&~func[3]& func[2]&~func[1]& func[0];
    wire inst_nor   = inst_reg& func[5]&~func[4]&~func[3]& func[2]& func[1]& func[0];
    wire inst_xor   = inst_reg& func[5]&~func[4]&~func[3]& func[2]& func[1]&~func[0];
    wire inst_sllv  = inst_reg&~func[5]&~func[4]&~func[3]& func[2]&~func[1]&~func[0];
    wire inst_srav  = inst_reg&~func[5]&~func[4]&~func[3]& func[2]& func[1]& func[0];
    wire inst_sra   = inst_reg&~func[5]&~func[4]&~func[3]&~func[2]& func[1]& func[0];
    wire inst_srl   = inst_reg&~func[5]&~func[4]&~func[3]&~func[2]& func[1]&~func[0];
    wire inst_srlv  = inst_reg&~func[5]&~func[4]&~func[3]& func[2]& func[1]&~func[0];

    // I-type 指令
    wire inst_andi  = inst_imm&~op[5]&~op[4]& op[3]& op[2]&~op[1]&~op[0];
    wire inst_addiu = inst_imm&~op[5]&~op[4]& op[3]&~op[2]&~op[1]& op[0];
    wire inst_ori   = inst_imm&~op[5]&~op[4]& op[3]& op[2]&~op[1]& op[0];
    wire inst_slti  = inst_imm&~op[5]&~op[4]& op[3]&~op[2]& op[1]&~op[0];
    wire inst_sltiu = inst_imm&~op[5]&~op[4]& op[3]&~op[2]& op[1]& op[0];
    wire inst_lui   = inst_imm&~op[5]&~op[4]& op[3]& op[2]& op[1]& op[0];
    wire inst_lb    = inst_imm& op[5]&~op[4]&~op[3]&~op[2]&~op[1]&~op[0];
    wire inst_lw    = inst_imm& op[5]&~op[4]&~op[3]&~op[2]& op[1]& op[0];
    wire inst_sb    = inst_imm& op[5]&~op[4]& op[3]&~op[2]&~op[1]&~op[0];
    wire inst_sw    = inst_imm& op[5]&~op[4]& op[3]&~op[2]& op[1]& op[0];
    wire inst_xori  = inst_imm&~op[5]&~op[4]& op[3]& op[2]& op[1]&~op[0];
    wire inst_lbu   = inst_imm& op[5]&~op[4]&~op[3]& op[2]&~op[1]&~op[0];
    wire inst_lh    = inst_imm& op[5]&~op[4]&~op[3]&~op[2]&~op[1]& op[0];
    wire inst_lhu   = inst_imm& op[5]&~op[4]&~op[3]& op[2]&~op[1]& op[0];
    wire inst_sh    = inst_imm& op[5]&~op[4]& op[3]&~op[2]&~op[1]& op[0];

    // 跳转指令生成
    wire inst_j     = ~op[5]&~op[4]&~op[3]&~op[2]& op[1]&~op[0];
    wire inst_jal   = ~op[5]&~op[4]&~op[3]&~op[2]& op[1]& op[0];
    wire inst_jr    = inst_reg&~func[5]&~func[4]& func[3]&~func[2]&~func[1]&~func[0];
    wire inst_beq   = ~op[5]&~op[4]&~op[3]& op[2]&~op[1]&~op[0];
    wire inst_bne   = ~op[5]&~op[4]&~op[3]& op[2]&~op[1]& op[0];

   
    /*------------------------------------------------------------------------------*/

    /*-------------------- 第二级译码逻辑：生成具体控制信号 --------------------*/
    // ALU R-type 指令
    wire inst_alu_reg   = (
        inst_add | inst_subu | inst_and | inst_slt |
        inst_or | inst_nor | inst_xor | inst_sllv |
        inst_sub | inst_addu | inst_sra | inst_srav |
        inst_srl | inst_srlv 
    );
    // ALU I-type 指令
    wire inst_alu_imm   = (
        inst_addiu | inst_ori | inst_sltiu | inst_lui |
        inst_andi | inst_xori | inst_slti
    );
    // 立即数符号扩展指令
    wire inst_imm_sign = (inst_lmem_s | inst_smem | inst_alu_imm);

    wire inst_mf        = (inst_mfhi | inst_mflo);
    // 移位使能信号
    wire inst_shift     = (
        inst_sll | inst_sllv | inst_sra | inst_srav |
        inst_srl | inst_srlv
    );
    // 加载指令(符号扩展)
    wire inst_lmem_s    = (inst_lb | inst_lw | inst_lh);
    // 加载指令(非符号扩展)
    wire inst_lmem_u    = (inst_lbu | inst_lhu);
    // 存储指令(符号扩展)
    wire inst_smem    = (inst_sb | inst_sw | inst_sh);

    // 逻辑运算指令
    wire inst_alu_logic = (
        inst_andi | inst_and | inst_ori | inst_or |
        inst_lui | inst_nor | inst_xor | inst_xori
    );
    // 数值运算指令
    wire inst_alu_arith = (
        inst_lmem_s | inst_lmem_u | inst_smem |
        inst_add | inst_subu | inst_slt | inst_addiu | 
        inst_sltiu | inst_sub | inst_addu | inst_slti
    );

    // 目的寄存器选择信号
    wire rtsel  = (
        inst_alu_imm | inst_lmem_s | inst_lmem_u | inst_smem 
    );

    // 立即数使能信号
    wire immsel = (
        inst_alu_imm | inst_lmem_s | inst_lmem_u | inst_smem
    );

    // 是否进行符号扩展信号
    wire sext   = ( inst_imm_sign );
    // 加载高半字使能信号
    wire upper  = (inst_lui);

    wire [`REG_BUS] imm_ext = (cpu_rst_n == `RST_ENABLE) ? `ZERO_WORD :
                               (upper == `UPPER_ENABLE) ? (imm << 16) :
                               (sext == `SIGNED_EXT) ? { { 16{imm[15]} }, imm} : {{16{1'b0}}, imm};

    // 生成相等使能信号
    wire equ = (cpu_rst_n == `RST_ENABLE) ? 1'b0:
               (inst_beq) ? (id_src1_o == id_src2_o):
               (inst_bne) ? (id_src1_o == id_src2_o):
               1'b0;

    // 是否为跳转指令
    wire inst_j_type = (inst_j | inst_jal | inst_jr | inst_bne | inst_beq);
                              
    // 操作类型alutype
    assign id_alutype_o[2] = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (inst_shift | inst_j_type); 
    assign id_alutype_o[1] = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (inst_alu_logic | inst_mf);
    assign id_alutype_o[0] = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (inst_alu_arith | inst_mf | inst_j_type);


    // 内部操作码aluop
    assign id_aluop_o[7]   = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_lb | inst_lw | inst_sb | inst_sw |
        inst_lbu | inst_lh | inst_lhu | inst_sh
    );
    assign id_aluop_o[6]   = (
        inst_j | inst_jr | inst_jal | inst_beq |
        inst_bne
    );
    assign id_aluop_o[5]   = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_slt | inst_sltiu | inst_sllv | inst_sra |
        inst_srav | inst_srlv | inst_srl | inst_slti
    );
    assign id_aluop_o[4]   = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_add | inst_subu | inst_and | inst_mult |
        inst_sll | inst_addiu | inst_ori | inst_lb |
        inst_lw | inst_sb | inst_sw | inst_sllv |
        inst_lbu | inst_multu | inst_sub | inst_addu |
        inst_sra | inst_srav | inst_srlv | inst_srl |
        inst_lh | inst_lhu | inst_sh
    );
    assign id_aluop_o[3]   = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_add | inst_subu | inst_and | inst_mfhi | 
        inst_mflo | inst_mthi | inst_mtlo | inst_addiu |
        inst_ori | inst_sb | inst_sw | inst_sub |
        inst_addu | inst_sh | inst_slti
    );
    assign id_aluop_o[2]   = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_and | inst_slt | inst_mult | inst_mfhi |
        inst_mflo | inst_mthi | inst_mtlo | inst_ori |
        inst_sltiu | inst_lui | inst_xor | inst_xori |
        inst_multu | inst_addu | inst_srl | inst_lhu |
        inst_bne
    );
    assign id_aluop_o[1]   = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_subu | inst_slt | inst_mthi | inst_mtlo |
        inst_sltiu | inst_lw | inst_sw | inst_or | inst_nor |
        inst_xor | inst_xori | inst_sub | inst_addu |
        inst_sra | inst_srlv | inst_lh | inst_jal |
        inst_beq
    );
    assign id_aluop_o[0]   = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_subu | inst_mflo  | inst_mtlo | inst_sll | 
        inst_addiu | inst_ori | inst_sltiu | inst_lui |
        inst_andi | inst_nor | inst_xori | inst_multu |
        inst_srav | inst_srlv | inst_lh | inst_sh |
        inst_jr | inst_beq
    );

    // 存储器到寄存器使能信号
    assign id_mreg_o       = (cpu_rst_n == `RST_ENABLE) ? 1'b0:
                             (inst_lmem_s | inst_lmem_u); 

    // 写HILO寄存器使能信号
    assign id_whilo_o      = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_mult | inst_mthi | inst_mtlo
    );

    // 写通用寄存器使能信号
    assign id_wreg_o       = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_alu_reg | inst_alu_imm | inst_mf | inst_shift |
        inst_lmem_u | inst_lmem_s | inst_jal
    );

    // 读通用寄存器堆端口1使能信号
    assign rreg1 = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_alu_reg | inst_alu_imm | inst_lmem_s | inst_lmem_u |
        inst_smem | inst_mult | inst_mthi | inst_mtlo | 
        inst_sb | inst_sw | inst_multu | inst_jr |
        inst_beq | inst_bne
    ) & ~inst_lui;

    // 读通用寄存器堆读端口2使能信号
    assign rreg2 = (cpu_rst_n == `RST_ENABLE) ? 1'b0 : (
        inst_alu_reg | inst_mult | inst_shift | inst_smem |
        inst_multu | inst_beq | inst_bne
    );

    // 生成子程序调用使能信号
    wire jal = inst_jal;

    // 生成转移地址选择信号
    assign jtsel_o[1] = inst_jr | inst_beq & equ | inst_bne & equ;
    assign jtsel_o[0] = inst_j | inst_jal | inst_beq & equ | inst_bne & equ;

    /*------------------------------------------------------------------------------*/

    // 读通用寄存器堆端口1的地址为rs字段，读端口2的地址为rt字段
    assign ra1   = (cpu_rst_n == `RST_ENABLE) ? `ZERO_WORD : rs;
    assign ra2   = (cpu_rst_n == `RST_ENABLE) ? `ZERO_WORD : rt;

    // 获得待写入目的寄存器的地址（rt或rd）
    assign id_wa_o      = (cpu_rst_n == `RST_ENABLE) ? `ZERO_WORD :
                          (rtsel == `RT_ENABLE) ? rt: 
                          (jal == `TRUE_V) ? 5'b11111:
                          rd;

    // 获得源操作数1。如果shift信号有效，则源操作数1为移位位数；否则为从读通用寄存器堆端口1获得的数据
    // 源操作数1也可能来自执行阶段前推的数据或者访存阶段前推的数据
    assign id_src1_o = (cpu_rst_n == `RST_ENABLE) ? `ZERO_WORD :
                       (inst_shift) ? {27'b0, sa} :
                       (fwrd1 == 2'b01) ? exe2id_wd_i :
                       (fwrd1 == 2'b10) ? mem2id_wd_i :
                       (fwrd1 == 2'b11) ? rd1: `ZERO_WORD;

    // 获得源操作数2。如果immsel信号有效，则源操作数1为立即数；否则为从读通用寄存器堆端口2获得的数据
    // 源操作数2也可能来自于执行阶段前推的数据或者访存阶段前推的数据
    assign id_src2_o = (cpu_rst_n == `RST_ENABLE) ? `ZERO_WORD :
                       (immsel == `IMM_ENABLE) ? imm_ext :
                       (fwrd2 == 2'b01) ? exe2id_wd_i :
                       (fwrd2 == 2'b10) ? mem2id_wd_i :
                       (fwrd2 == 2'b11) ? rd2 : `ZERO_WORD;

    // 获得访存阶段要存入数据存储器的数据，可能来自执行阶段前推的数据，也可能来自访存阶段前推的数据，
    // 也可能来自通用寄存器的读端口2
    assign id_din_o = (cpu_rst_n == `RST_ENABLE) ? `ZERO_WORD :
                      (fwrd2 == 2'b01) ? exe2id_wd_i :
                      (fwrd2 == 2'b10) ? mem2id_wd_i :
                      (fwrd2 == 2'b11) ? rd2 : `ZERO_WORD;
                      
    // 生成计算转移地址所需信号
    wire [`INST_ADDR_BUS] pc_plus_8 = id_pc_plus_4_i + 4;
    wire [`JUMP_BUS] instr_index = id_inst[25 : 0];
    wire [`INST_ADDR_BUS] imm_jump = {{14{imm[15]}}, imm, 2'b0};

    // 获得转移地址
    assign jump_addr_1_o = {id_pc_plus_4_i[31 : 28], instr_index, 2'b00};
    assign jump_addr_2_o = id_pc_plus_4_i + imm_jump;
    assign jump_addr_3_o = id_src1_o;

    // 生成子程序调用的返回地址
    assign ret_addr_o = pc_plus_8;

    
endmodule
