

`include "parameters.svh"

module meds_s1_axil_w_ch (
    input  logic                        Aclk,
    input  logic                        Aresetn,

    input  logic [`DATA_WIDTH-1:0]      Wdata,
    input  logic [`STRB_WIDTH-1:0]      Wstrb,
    input  logic                        Wvalid,
    output logic                        Wready,

    output logic [`DATA_WIDTH-1:0]      WCapturedData,
    output logic [`STRB_WIDTH-1:0]      WCapturedStrb,
    output logic                        WCaptured,
    input  logic                        WConsume   // pulse: clear the buffer
);

    localparam [0:0] IDLE     = 1'd0,
                      CAPTURED = 1'd1;

    reg                     state, state_n;
    reg [`DATA_WIDTH-1:0]  data_reg, data_reg_n;
    reg [`STRB_WIDTH-1:0]  strb_reg, strb_reg_n;

    always @(posedge Aclk or negedge Aresetn) begin
        if (!Aresetn) begin
            state    <= IDLE;
            data_reg <= 0;
            strb_reg <= 0;
        end else begin
            state    <= state_n;
            data_reg <= data_reg_n;
            strb_reg <= strb_reg_n;
        end
    end

    always @(*) begin
        state_n    = state;
        data_reg_n = data_reg;
        strb_reg_n = strb_reg;

        Wready = 1'b0;

        case (state)

            IDLE: begin
                Wready = 1'b1;
                if (Wvalid) begin
                    data_reg_n = Wdata;
                    strb_reg_n = Wstrb;
                    state_n    = CAPTURED;
                end
            end

            CAPTURED: begin
                Wready = 1'b0;
                if (WConsume) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign WCapturedData = data_reg;
    assign WCapturedStrb = strb_reg;
    assign WCaptured     = (state == CAPTURED);

endmodule
