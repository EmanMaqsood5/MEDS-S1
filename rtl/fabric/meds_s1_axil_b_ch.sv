

`include "parameters.svh"

module meds_s1_axil_b_ch (
    input  logic                        Aclk,
    input  logic                        Aresetn,

    // From meds_s1_axil_aw_ch
    input  logic [`ADDR_WIDTH-1:0]      AwCapturedAddr,
    input  logic                        AwCaptured,
    output logic                        AwConsume,

    // From meds_s1_axil_w_ch
    input  logic [`DATA_WIDTH-1:0]      WCapturedData,
    input  logic [`STRB_WIDTH-1:0]      WCapturedStrb,
    input  logic                        WCaptured,
    output logic                        WConsume,

    // B channel
    output logic [1:0]                  Bresp,
    output logic                        Bvalid,
    input  logic                        Bready,

    // Internal write-commit interface (to register storage)
    output logic [`ADDR_WIDTH-1:0]      WrAddr,
    output logic [`DATA_WIDTH-1:0]      WrData,
    output logic [`STRB_WIDTH-1:0]      WrStrb,
    output logic                        WrEn,        // one-cycle commit pulse
    input  logic                        WrAddrValid  // 1 = in range -> OKAY, else DECERR
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;

    localparam [1:0] IDLE   = 2'd0,
                      COMMIT = 2'd1,
                      RESP   = 2'd2;

    reg [1:0]               state, state_n;
    reg [`ADDR_WIDTH-1:0]   addr_reg, addr_reg_n;
    reg [`DATA_WIDTH-1:0]   data_reg, data_reg_n;
    reg [`STRB_WIDTH-1:0]   strb_reg, strb_reg_n;
    reg [1:0]                bresp_reg, bresp_reg_n;

    always @(posedge Aclk or negedge Aresetn) begin
        if (!Aresetn) begin
            state     <= IDLE;
            addr_reg  <= 0;
            data_reg  <= 0;
            strb_reg  <= 0;
            bresp_reg <= RESP_OKAY;
        end else begin
            state     <= state_n;
            addr_reg  <= addr_reg_n;
            data_reg  <= data_reg_n;
            strb_reg  <= strb_reg_n;
            bresp_reg <= bresp_reg_n;
        end
    end

    always @(*) begin
        state_n     = state;
        addr_reg_n  = addr_reg;
        data_reg_n  = data_reg;
        strb_reg_n  = strb_reg;
        bresp_reg_n = bresp_reg;

        AwConsume = 1'b0;
        WConsume  = 1'b0;
        WrEn      = 1'b0;
        Bvalid    = 1'b0;

        case (state)

            IDLE: begin
                if (AwCaptured && WCaptured) begin
                    addr_reg_n = AwCapturedAddr;
                    data_reg_n = WCapturedData;
                    strb_reg_n = WCapturedStrb;
                    AwConsume  = 1'b1;
                    WConsume   = 1'b1;
                    state_n    = COMMIT;
                end
            end

            COMMIT: begin
                WrEn = 1'b1;
                if (WrAddrValid) bresp_reg_n = RESP_OKAY;
                else             bresp_reg_n = RESP_DECERR;
                state_n = RESP;
            end

            RESP: begin
                Bvalid = 1'b1;
                if (Bready) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign WrAddr = addr_reg;
    assign WrData = data_reg;
    assign WrStrb = strb_reg;
    assign Bresp  = bresp_reg;

endmodule
