module Top_module (
    input  CLOCK_50,
    input  [3:0] KEY,     // KEY[0]: Reset, KEY[1]: Chụp
    inout  [35:0] GPIO_0, // Camera (JP1)
    inout  [35:0] GPIO_1, // UART (JP2)
    output [6:0] HEX0,
    output [9:0] LEDR
);

    // --- KHAI BÁO TÍN HIỆU ---
    wire rst_n = KEY[0];
    wire btn_capture = !KEY[1]; // Nút nhấn mức 1 khi nhấn

    // Phát hiện cạnh lên của nút nhấn (Nhấn 1 cái là bắt)
    reg btn_prev;
    wire btn_trigger = btn_capture && !btn_prev;
    always @(posedge CLOCK_50) btn_prev <= btn_capture;

    // --- 1. MÁY TRẠNG THÁI TRUNG TÂM (MASTER FSM) ---
    // Điều phối việc: Chờ nút -> Ra lệnh chụp -> Chờ chụp xong -> AI xử lý -> Hiển thị
    
    localparam S_IDLE        = 0;
    localparam S_WAIT_CAM    = 1; // Chờ camera chụp xong frame
    localparam S_WAIT_AI     = 2; // Chờ AI xử lý xong (optional - có thể bỏ)
    
    reg [1:0] state;
    reg sys_capture_req; // Lệnh yêu cầu camera chụp
    
    // Tín hiệu UART (tùy chọn - có thể dùng để debug)
    reg  uart_start;
    reg  [7:0] uart_data;
    wire uart_busy;
    wire uart_tx_pin;
    
    // Tín hiệu Camera
    wire capture_done_sig; 
    wire [783:0] img_data;

    always @(posedge CLOCK_50) begin
        if (!rst_n) begin
            state <= S_IDLE;
            sys_capture_req <= 0;
            uart_start <= 0;
        end else begin
            case (state)
                // TRẠNG THÁI 0: CHỜ NGƯỜI DÙNG NHẤN NÚT
                S_IDLE: begin
                    sys_capture_req <= 0; // Tắt lệnh chụp
                    uart_start <= 0;
                    if (btn_trigger) begin // Nếu phát hiện nhấn nút
                        sys_capture_req <= 1; // Bật lệnh chụp (Giữ luôn ở mức 1)
                        state <= S_WAIT_CAM;  // Chuyển sang chờ camera
                    end
                end

                // TRẠNG THÁI 1: CHỜ CAMERA CHỤP XONG
                S_WAIT_CAM: begin
                    // sys_capture_req vẫn đang là 1 để camera bắt được VSYNC
                    if (capture_done_sig) begin
                        sys_capture_req <= 0; // Chụp xong rồi thì hạ lệnh xuống
                        // AI sẽ tự động bắt đầu khi nhận được capture_done_sig
                        state <= S_WAIT_AI; // Chờ AI xử lý (hoặc về IDLE luôn)
                    end
                end
                
                // TRẠNG THÁI 2: CHỜ AI XỬ LÝ (Tùy chọn)
                S_WAIT_AI: begin
                    if (ai_done) begin
                        state <= S_IDLE; // AI đã xử lý xong, về IDLE
                    end
                end
            endcase
        end
    end

    // --- 2. CẤU HÌNH CAMERA (GPIO 0) ---
    assign GPIO_0[0] = 1'b1; // RESET
    assign GPIO_0[1] = 1'b0; // PWDN
    
    // Tránh xung đột chân XCLK (Pin 18)
    assign GPIO_0[15] = 1'bz; 

    wire cfg_done;
    ov2640_config u_cfg (
        .clk(CLOCK_50), .rst_n(rst_n),
        .sioc(GPIO_0[11]), .siod(GPIO_0[10]),
        .config_done(cfg_done)
    );
    assign LEDR[0] = cfg_done; 

    // --- 3. THU ẢNH (GPIO 0) ---
    // Dữ liệu pixel
    wire [7:0] cam_d = {
        GPIO_0[23], GPIO_0[22], GPIO_0[21], GPIO_0[20], 
        GPIO_0[19], GPIO_0[18], GPIO_0[17], GPIO_0[16]
    };

    camera_capture u_cam (
        .pclk(GPIO_0[14]), 
        .vsync(GPIO_0[12]), 
        .href(GPIO_0[13]), 
        .d_in(cam_d),
        .capture_en(sys_capture_req), // Nối vào biến điều khiển của FSM
        .img_out(img_data),
        .done_tick(capture_done_sig)
    );
    assign LEDR[1] = capture_done_sig; // Đèn này sẽ sáng khi chụp xong

    // --- 4. AI & HIỂN THỊ ---
    wire ai_done;
    ai_mnist u_ai (
        .clk(CLOCK_50), 
        .rst_n(rst_n),
        .start(capture_done_sig), 
        .img_in(img_data), 
        .hex_out(HEX0),
        .done(ai_done)
    );
    assign LEDR[2] = ai_done; // Đèn báo AI đã tính xong

    // --- 5. UART TX (GPIO 1 - Pin 1) ---
    uart_tx u_uart (
        .clk(CLOCK_50), .start(uart_start), .data(uart_data),
        .tx(uart_tx_pin), .busy(uart_busy)
    );
    assign GPIO_1[0] = uart_tx_pin;

endmodule