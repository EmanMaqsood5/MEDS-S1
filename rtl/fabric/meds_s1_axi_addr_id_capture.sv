

module meds_s1_axi_addr_id_capture #(
    parameter int ADDR_W = 40,
    parameter int ID_W = 6
) (
    input logic clk_i,
    input logic rst_ni,

    input logic [ADDR_W-1:0] addr,
    input logic [ID_W-1:0] id,
    input logic valid,
    output logic ready,

    output logic [ADDR_W-1:0] captured_addr,
    output logic [ID_W-1:0] captured_id,
    output logic captured,
    input logic consume // pulse: clear the buffer
);

    localparam [0:0] IDLE = 1'd0,
                      CAPTURED = 1'd1;

    logic state, state_n;
    logic [ADDR_W-1:0] addr_reg, addr_reg_n;
    logic [ID_W-1:0] id_reg, id_reg_n;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
            addr_reg <= '0;
            id_reg <= '0;
        end else begin
            state <= state_n;
            addr_reg <= addr_reg_n;
            id_reg <= id_reg_n;
        end
    end

    always_comb begin
        state_n = state;
        addr_reg_n = addr_reg;
        id_reg_n = id_reg;

        ready = 1'b0;

        case (state)
            IDLE: begin
                ready = 1'b1;
                if (valid) begin
                    addr_reg_n = addr;
                    id_reg_n = id;
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

    assign captured_addr = addr_reg;
    assign captured_id = id_reg;
    assign captured = (state == CAPTURED);

endmodule
