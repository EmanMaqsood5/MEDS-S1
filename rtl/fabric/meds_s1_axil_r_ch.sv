

`include "parameters.svh"

module meds_s1_axil_r_ch (
    input  logic                        Aclk,
    input  logic                        Aresetn,

    // From meds_s1_axil_ar_ch
    input  logic [`ADDR_WIDTH-1:0]      ArCapturedAddr,
    input  logic                        ArCaptured,
    output logic                        ArConsume,

    // Read data channel
    output logic [`DATA_WIDTH-1:0]      Rdata,
    output logic [1:0]                  Rresp,
    output logic                        Rvalid,
    input  logic                        Rready,

    // Internal read-lookup interface (to register storage)
    output logic [`ADDR_WIDTH-1:0]      RdAddr,      // address presented to storage
    input  logic [`DATA_WIDTH-1:0]      RdData,      // data for RdAddr (combinational)
    input  logic                        RdAddrValid  // 1 = in range -> OKAY, else DECERR
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;

    localparam [1:0] IDLE   = 2'd0,
                      LOOKUP = 2'd1,
                      RESP   = 2'd2;

    reg [1:0]               state, state_n;
    reg [`ADDR_WIDTH-1:0]   addr_reg, addr_reg_n;
    reg [`DATA_WIDTH-1:0]   data_reg, data_reg_n;
    reg [1:0]                resp_reg, resp_reg_n;

    always @(posedge Aclk or negedge Aresetn) begin
        if (!Aresetn) begin
            state    <= IDLE;
            addr_reg <= 0;
            data_reg <= 0;
            resp_reg <= RESP_OKAY;
        end else begin
            state    <= state_n;
            addr_reg <= addr_reg_n;
            data_reg <= data_reg_n;
            resp_reg <= resp_reg_n;
        end
    end

    always @(*) begin
        state_n    = state;
        addr_reg_n = addr_reg;
        data_reg_n = data_reg;
        resp_reg_n = resp_reg;

        ArConsume = 1'b0;
        Rvalid    = 1'b0;

        case (state)

            IDLE: begin
                if (ArCaptured) begin
                    addr_reg_n = ArCapturedAddr;
                    ArConsume  = 1'b1;
                    state_n    = LOOKUP;
                end
            end

            LOOKUP: begin
                
                data_reg_n = RdData;
                if (RdAddrValid) resp_reg_n = RESP_OKAY;
                else             resp_reg_n = RESP_DECERR;
                state_n = RESP;
            end

            RESP: begin
                Rvalid = 1'b1;
                if (Rready) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign RdAddr = addr_reg;
    assign Rdata  = data_reg;
    assign Rresp  = resp_reg;

endmodule
