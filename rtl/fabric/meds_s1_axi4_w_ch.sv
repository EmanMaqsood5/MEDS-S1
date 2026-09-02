
`include "axi4_params.svh"

module meds_s1_axi4_w_ch (
    input logic clk_i,
    input logic rst_ni,

    input logic [`AXI_DATA_W-1:0] wdata,
    input logic [`AXI_STRB_W-1:0] wstrb,
    input logic wlast,
    input logic wvalid,
    output logic wready,

    output logic [`AXI_DATA_W-1:0] WCapturedData,
    output logic [`AXI_STRB_W-1:0] WCapturedStrb,
    output logic WCapturedLast,
    output logic WCaptured,
    input logic WConsume // pulse: clear the buffer
);

    localparam [0:0] IDLE = 1'd0,
                      CAPTURED = 1'd1;

    logic state, state_n;
    logic [`AXI_DATA_W-1:0] data_reg, data_reg_n;
    logic [`AXI_STRB_W-1:0] strb_reg, strb_reg_n;
    logic last_reg, last_reg_n;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            data_reg <= '0;
            strb_reg <= '0;
            last_reg <= 1'b0;
        end else begin
            state <= state_n;
            data_reg <= data_reg_n;
            strb_reg <= strb_reg_n;
            last_reg <= last_reg_n;
        end
    end

    always_comb begin
        state_n = state;
        data_reg_n = data_reg;
        strb_reg_n = strb_reg;
        last_reg_n = last_reg;

        wready = 1'b0;

        case (state)

            IDLE: begin
                wready = 1'b1;
                if (wvalid) begin
                    data_reg_n = wdata;
                    strb_reg_n = wstrb;
                    last_reg_n = wlast;
                    state_n = CAPTURED;
                end
            end

            CAPTURED: begin
                wready = 1'b0;
                if (WConsume) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign WCapturedData = data_reg;
    assign WCapturedStrb = strb_reg;
    assign WCapturedLast = last_reg;
    assign WCaptured = (state == CAPTURED);

endmodule
