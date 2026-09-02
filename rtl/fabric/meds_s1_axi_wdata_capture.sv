

module meds_s1_axi_wdata_capture #(
    parameter int DATA_W = 256,
    parameter int STRB_W = DATA_W/8
) (
    input logic clk_i,
    input logic rst_ni,

    input logic [DATA_W-1:0] data,
    input logic [STRB_W-1:0] strb,
    input logic valid,
    output logic ready,

    output logic [DATA_W-1:0] captured_data,
    output logic [STRB_W-1:0] captured_strb,
    output logic captured,
    input logic consume // pulse: clear the buffer
);

    localparam [0:0] IDLE = 1'd0,
                      CAPTURED = 1'd1;

    logic state, state_n;
    logic [DATA_W-1:0] data_reg, data_reg_n;
    logic [STRB_W-1:0] strb_reg, strb_reg_n;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            data_reg <= '0;
            strb_reg <= '0;
        end else begin
            state <= state_n;
            data_reg <= data_reg_n;
            strb_reg <= strb_reg_n;
        end
    end

    always_comb begin
        state_n = state;
        data_reg_n = data_reg;
        strb_reg_n = strb_reg;

        ready = 1'b0;

        case (state)
            IDLE: begin
                ready = 1'b1;
                if (valid) begin
                    data_reg_n = data;
                    strb_reg_n = strb;
                    state_n = CAPTURED;
                end
            end

            CAPTURED: begin
                ready = 1'b0;
                if (consume) state_n = IDLE;
            end

            default: state_n = IDLE;
        endcase
    end

    assign captured_data = data_reg;
    assign captured_strb = strb_reg;
    assign captured = (state == CAPTURED);

endmodule
