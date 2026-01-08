module uart_tx (
    input wire clk,       // Clock 50MHz
    input wire start,     // Xung kích hoạt (chỉ cần bật lên 1 trong 1 chu kỳ clock)
    input wire [7:0] data,// Byte dữ liệu cần gửi
    output reg tx,        // Chân phát tín hiệu (Nối ra GPIO)
    output reg busy       // Báo bận (1 = đang gửi, 0 = rảnh)
);

    // Tính toán số chu kỳ clock cho 1 bit ở tốc độ 115200
    // 50,000,000 / 115200 = 434
    parameter CLKS_PER_BIT = 434;

    reg [2:0] state;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] tx_data;

    // Định nghĩa trạng thái
    localparam S_IDLE  = 3'd0;
    localparam S_START = 3'd1;
    localparam S_DATA  = 3'd2;
    localparam S_STOP  = 3'd3;

    initial begin
        tx = 1;      // Trạng thái nghỉ của UART là mức cao
        state = 0;
        busy = 0;
    end

    always @(posedge clk) begin
        case (state)
            // --- TRẠNG THÁI NGHỈ ---
            S_IDLE: begin
                tx <= 1;
                clk_cnt <= 0;
                bit_idx <= 0;
                
                if (start == 1'b1) begin
                    tx_data <= data; // Chốt dữ liệu
                    state <= S_START;
                    busy <= 1;       // Báo bận
                end else begin
                    busy <= 0;
                end
            end

            // --- BIT START (Kéo xuống 0) ---
            S_START: begin
                tx <= 0;
                if (clk_cnt < CLKS_PER_BIT - 1) begin
                    clk_cnt <= clk_cnt + 1;
                end else begin
                    clk_cnt <= 0;
                    state <= S_DATA;
                end
            end

            // --- 8 BIT DỮ LIỆU (Gửi từ Bit 0 đến Bit 7) ---
            S_DATA: begin
                tx <= tx_data[bit_idx]; // Gửi từng bit
                
                if (clk_cnt < CLKS_PER_BIT - 1) begin
                    clk_cnt <= clk_cnt + 1;
                end else begin
                    clk_cnt <= 0;
                    if (bit_idx < 7) begin
                        bit_idx <= bit_idx + 1;
                    end else begin
                        bit_idx <= 0;
                        state <= S_STOP;
                    end
                end
            end

            // --- BIT STOP (Kéo lên 1) ---
            S_STOP: begin
                tx <= 1;
                if (clk_cnt < CLKS_PER_BIT - 1) begin
                    clk_cnt <= clk_cnt + 1;
                end else begin
                    state <= S_IDLE; // Quay về nghỉ, sẵn sàng gửi byte mới
                    busy <= 0;       // Xả bận
                end
            end
            
            default: state <= S_IDLE;
        endcase
    end
endmodule