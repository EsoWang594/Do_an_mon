module ai_mnist (
    input wire clk,
    input wire rst_n,
    input wire start,           // Tín hiệu bắt đầu tính toán
    input wire [783:0] img_in,  // Ảnh đầu vào 28x28 (784 bit)
    output reg [6:0] hex_out,   // Ra LED 7 đoạn
    output reg done             // Báo hiệu đã tính xong
);

    // --- FSM STATES ---
    localparam S_IDLE       = 3'd0;
    localparam S_PREPROC    = 3'd1;  // Tiền xử lý ảnh
    localparam S_LAYER1     = 3'd2;  // Tính toán Layer 1 (784 -> 32)
    localparam S_LAYER2     = 3'd3;  // Tính toán Layer 2 (32 -> 10)
    localparam S_ARGMAX     = 3'd4;  // Tìm số có điểm cao nhất
    localparam S_DISPLAY    = 3'd5;  // Hiển thị kết quả
    
    reg [2:0] state;
    
    // --- BIẾN ĐẾM VÀ CHỈ SỐ ---
    reg [9:0] pixel_idx;      // Đếm pixel (0-783)
    reg [3:0] neuron_idx;     // Đếm neuron trong layer (0-9 cho cả layer1 và layer2)
    reg [3:0] weight_idx;     // Đếm weight trong neuron hiện tại (0-9 cho layer2)
    
    // --- DỮ LIỆU TRUNG GIAN ---
    reg [783:0] img_normalized;  // Ảnh đã normalize
    reg [15:0] accumulator;      // Thanh ghi tích lũy MAC
    reg [15:0] layer1_out [0:9]; // Output của layer 1 (10 neurons - giảm để tiết kiệm tài nguyên)
    reg [15:0] layer2_out [0:9];  // Output của layer 2 (10 neurons)
    reg [3:0] digit_result;      // Kết quả số nhận diện (0-9)
    
    // --- MAC OPERATION ---
    reg [7:0] weight_value;
    reg img_bit;
    wire [15:0] mac_result;
    
    // Tính MAC: accumulator = accumulator + weight * input
    assign mac_result = accumulator + (weight_value * img_bit);
    
    // --- PATTERN MATCHING WEIGHTS (SIMPLIFIED) ---
    // Tính toán weight dựa trên vị trí pixel và neuron
    always @(*) begin
        weight_value = 8'd0;
        img_bit = img_normalized[pixel_idx];
        
        if (state == S_LAYER1) begin
            // Layer 1: Pattern matching cho từng số
            case (neuron_idx)
                0: begin // Pattern số 0: vòng tròn
                    if ((pixel_idx / 28 < 4 || pixel_idx / 28 > 23 || 
                         pixel_idx % 28 < 4 || pixel_idx % 28 > 23) &&
                        (pixel_idx / 28 >= 7 && pixel_idx / 28 <= 20 &&
                         pixel_idx % 28 >= 7 && pixel_idx % 28 <= 20))
                        weight_value = 8'd50;
                end
                1: begin // Pattern số 1: đường thẳng giữa
                    if (pixel_idx % 28 >= 12 && pixel_idx % 28 <= 15)
                        weight_value = 8'd60;
                end
                2: begin // Pattern số 2
                    if ((pixel_idx / 28 < 10 && pixel_idx % 28 > 10) ||
                        (pixel_idx / 28 >= 10 && pixel_idx / 28 < 14 && pixel_idx % 28 < 18))
                        weight_value = 8'd45;
                end
                3: begin // Pattern số 3
                    if ((pixel_idx / 28 < 10 && pixel_idx % 28 > 12) ||
                        (pixel_idx / 28 >= 10 && pixel_idx / 28 < 18 && pixel_idx % 28 > 12) ||
                        (pixel_idx / 28 >= 18 && pixel_idx % 28 > 12))
                        weight_value = 8'd45;
                end
                4: begin // Pattern số 4
                    if ((pixel_idx / 28 < 14 && pixel_idx % 28 > 12) ||
                        (pixel_idx / 28 >= 14 && pixel_idx % 28 < 18))
                        weight_value = 8'd50;
                end
                5: begin // Pattern số 5
                    if ((pixel_idx / 28 < 10 && pixel_idx % 28 < 15) ||
                        (pixel_idx / 28 >= 10 && pixel_idx / 28 < 18 && pixel_idx % 28 > 10) ||
                        (pixel_idx / 28 >= 18 && pixel_idx % 28 < 15))
                        weight_value = 8'd45;
                end
                6: begin // Pattern số 6
                    if ((pixel_idx / 28 >= 10 && (pixel_idx % 28 < 8 || pixel_idx % 28 > 19)) ||
                        (pixel_idx / 28 >= 18 && pixel_idx % 28 < 8))
                        weight_value = 8'd50;
                end
                7: begin // Pattern số 7
                    if (pixel_idx / 28 < 10 && pixel_idx % 28 > 10 && 
                        (pixel_idx % 28 - pixel_idx / 28) > 5)
                        weight_value = 8'd50;
                end
                8: begin // Pattern số 8
                    if ((pixel_idx / 28 < 14 && (pixel_idx % 28 < 8 || pixel_idx % 28 > 19)) ||
                        (pixel_idx / 28 >= 14 && (pixel_idx % 28 < 8 || pixel_idx % 28 > 19)))
                        weight_value = 8'd50;
                end
                9: begin // Pattern số 9
                    if ((pixel_idx / 28 < 14 && (pixel_idx % 28 < 8 || pixel_idx % 28 > 19)) ||
                        (pixel_idx / 28 >= 14 && pixel_idx % 28 > 19))
                        weight_value = 8'd50;
                end
                default: weight_value = 8'd0;
            endcase
        end else if (state == S_LAYER2) begin
            // Layer 2: Kết hợp các pattern (10 inputs -> 10 outputs)
            if (weight_idx == neuron_idx)
                weight_value = 8'd30; // Kết nối mạnh với neuron tương ứng
            else
                weight_value = 8'd5;  // Kết nối yếu với neuron khác
        end
    end
    
    // --- DECODER 7-SEG ---
    always @(*) begin
        case (digit_result)
            4'd0: hex_out = 7'b1000000; // 0
            4'd1: hex_out = 7'b1111001; // 1
            4'd2: hex_out = 7'b0100100; // 2
            4'd3: hex_out = 7'b0110000; // 3
            4'd4: hex_out = 7'b0011001; // 4
            4'd5: hex_out = 7'b0010010; // 5
            4'd6: hex_out = 7'b0000010; // 6
            4'd7: hex_out = 7'b1111000; // 7
            4'd8: hex_out = 7'b0000000; // 8
            4'd9: hex_out = 7'b0010000; // 9
            default: hex_out = 7'b1111111; // Tắt
        endcase
    end
    
    // --- MAIN FSM ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            pixel_idx <= 0;
            neuron_idx <= 0;
            weight_idx <= 0;
            accumulator <= 0;
            done <= 0;
            digit_result <= 4'd0;
            img_normalized <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= S_PREPROC;
                        pixel_idx <= 0;
                        neuron_idx <= 0;
                        weight_idx <= 0;
                    end
                end
                
                S_PREPROC: begin
                    // Normalize ảnh: đảo bit để phù hợp với MNIST (0=trắng, 1=đen)
                    img_normalized[pixel_idx] <= ~img_in[pixel_idx];
                    if (pixel_idx == 783) begin
                        pixel_idx <= 0;
                        neuron_idx <= 0;
                        accumulator <= 0;
                        state <= S_LAYER1;
                    end else
                        pixel_idx <= pixel_idx + 1;
                end
                
                S_LAYER1: begin
                    // Tính toán Layer 1: 784 inputs -> 32 outputs
                    if (pixel_idx == 0) begin
                        // Bắt đầu neuron mới
                        accumulator <= 0;
                    end
                    
                    // MAC operation
                    accumulator <= mac_result;
                    
                    if (pixel_idx == 783) begin
                        // Hoàn thành neuron hiện tại, apply ReLU và lưu
                        if (accumulator[15]) // Nếu âm thì = 0 (ReLU)
                            layer1_out[neuron_idx] <= 0;
                        else
                            layer1_out[neuron_idx] <= accumulator[15:0];
                        
                        if (neuron_idx == 9) begin
                            // Hoàn thành layer 1
                            neuron_idx <= 0;
                            pixel_idx <= 0;
                            weight_idx <= 0;
                            accumulator <= 0;
                            state <= S_LAYER2;
                        end else begin
                            neuron_idx <= neuron_idx + 1;
                            pixel_idx <= 0;
                            accumulator <= 0;
                        end
                    end else
                        pixel_idx <= pixel_idx + 1;
                end
                
                S_LAYER2: begin
                    // Tính toán Layer 2: 10 inputs -> 10 outputs
                    if (weight_idx == 0) begin
                        accumulator <= 0;
                    end
                    
                    // MAC operation với output của layer 1 (threshold)
                    accumulator <= accumulator + (weight_value * (layer1_out[weight_idx] > 16'd100 ? 1 : 0));
                    
                    if (weight_idx == 9) begin
                        // Hoàn thành neuron hiện tại, lưu output
                        layer2_out[neuron_idx] <= accumulator;
                        
                        if (neuron_idx == 9) begin
                            // Hoàn thành layer 2
                            state <= S_ARGMAX;
                            neuron_idx <= 0;
                            accumulator <= layer2_out[0];
                            digit_result <= 0;
                        end else begin
                            neuron_idx <= neuron_idx + 1;
                            weight_idx <= 0;
                            accumulator <= 0;
                        end
                    end else
                        weight_idx <= weight_idx + 1;
                end
                
                S_ARGMAX: begin
                    // Tìm neuron có giá trị lớn nhất
                    if (layer2_out[neuron_idx] > accumulator) begin
                        accumulator <= layer2_out[neuron_idx];
                        digit_result <= neuron_idx[3:0];
                    end
                    
                    if (neuron_idx == 9) begin
                        state <= S_DISPLAY;
                    end else
                        neuron_idx <= neuron_idx + 1;
                end
                
                S_DISPLAY: begin
                    // Hiển thị kết quả (đã được decode trong always @(*))
                    done <= 1;
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule