module camera_capture (
    input wire pclk,            // Pixel Clock (Nối vào DCLK của Camera)
    input wire vsync,           // Frame Sync (Đồng bộ khung hình)
    input wire href,            // Line Sync (Đồng bộ hàng)
    input wire [7:0] d_in,      // Dữ liệu ảnh 8 bit (D7-D0)
    
    input wire capture_en,      // Tín hiệu cho phép chụp (từ nút nhấn)
    output reg [783:0] img_out, // Buffer chứa ảnh 28x28 (784 bit)
    output reg done_tick        // Báo hiệu đã chụp xong
);

    // --- KHAI BÁO BIẾN ---
    reg [9:0] x_cnt;      // Đếm cột (Pixel trong 1 dòng)
    reg [9:0] y_cnt;      // Đếm dòng (Số dòng trong 1 khung)
    reg [9:0] pixel_idx;  // Vị trí pixel trong ảnh kết quả (0 -> 783)
    reg href_last;        // Trạng thái cũ của HREF để bắt sườn xuống
    
    // --- CẤU HÌNH NGƯỠNG SÁNG ---
    // So sánh độ sáng để chuyển thành Nhị phân (Đen/Trắng)
    // < THRESHOLD = Mực (Đen - Bit 1)
    // > THRESHOLD = Giấy (Trắng - Bit 0)
    // Nếu ảnh bị nhiễu nhiều chấm đen, hãy GIẢM số này xuống (vd: 60)
    parameter THRESHOLD = 8'd80; 

    // --- KHỐI XỬ LÝ CHÍNH (ĐỒNG BỘ THEO PCLK) ---
    always @(posedge pclk) begin
        // Lưu trạng thái HREF cũ để phát hiện sườn xuống
        href_last <= href;

        // 1. GẶP VSYNC -> RESET TOÀN BỘ (Bắt đầu khung hình mới)
        if (vsync) begin
            x_cnt <= 0;
            y_cnt <= 0;
            // Nếu đang bật chế độ chụp thì reset index để chuẩn bị ghi
            if (capture_en) begin
                pixel_idx <= 0;
                done_tick <= 0;
            end
        end 
        else begin
            // 2. KHI ĐANG Ở TRONG DÒNG (HREF = 1) -> TĂNG X, LẤY DỮ LIỆU
            if (href) begin
                x_cnt <= x_cnt + 1;
                
                // LOGIC CROP & DOWNSCALE:
                // Camera OV2640 thường ra 320x240 (QVGA) hoặc xấp xỉ.
                // Ta cắt vùng trung tâm: X[48..272], Y[8..232] (Kích thước 224x224)
                // Sau đó lấy mẫu mỗi 8 pixel (224 / 8 = 28 pixel)
                
                if (capture_en && !done_tick) begin
                    // Kiểm tra xem pixel hiện tại có nằm trong vùng Crop không
                    if ((x_cnt >= 48) && (x_cnt < 272) && (y_cnt >= 8) && (y_cnt < 232)) begin
                        
                        // Downscale: Chỉ lấy pixel đầu tiên của mỗi ô 8x8
                        // Điều kiện: 3 bit cuối của x_cnt và y_cnt đều bằng 0 (nghĩa là chia hết cho 8)
                        if ((x_cnt[2:0] == 3'b000) && (y_cnt[2:0] == 3'b000)) begin
                            
                            if (pixel_idx < 784) begin
                                // Nhị phân hóa: 
                                // Nếu tối hơn ngưỡng -> 1 (Mực). Sáng hơn -> 0 (Giấy)
                                img_out[pixel_idx] <= (d_in < THRESHOLD) ? 1'b1 : 1'b0;
                                
                                pixel_idx <= pixel_idx + 1;
                            end
                        end
                    end
                end
            end 
            // 3. KHI HẾT DÒNG (Sườn xuống của HREF: Từ 1 xuống 0) -> TĂNG Y
            else if (href_last && !href) begin
                y_cnt <= y_cnt + 1; // Tăng số dòng lên
                x_cnt <= 0;         // Reset cột về 0 để đón dòng mới
            end
        end
        
        // 4. KIỂM TRA HOÀN THÀNH
        if (pixel_idx == 784) begin
            done_tick <= 1; // Báo cho module khác biết là đã chụp xong
        end
    end

endmodule