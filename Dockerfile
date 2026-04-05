# 1. Khởi tạo từ hệ điều hành Ubuntu 22.04 (Nhẹ, ổn định)
FROM ubuntu:22.04

# 2. Cấu hình môi trường không tương tác để không bị kẹt khi cài đặt
ENV DEBIAN_FRONTEND="noninteractive"
ENV TZ="Asia/Ho_Chi_Minh"

# 3. Cài đặt các gói phần mềm nền tảng và Java 17 (Bắt buộc cho Android SDK)
RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip libglu1-mesa openjdk-17-jdk wget \
    && rm -rf /var/lib/apt/lists/*

# 4. Thiết lập đường dẫn môi trường cho Android SDK
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# 5. Tải và cài đặt Android Command Line Tools từ Google
RUN mkdir -p $ANDROID_HOME/cmdline-tools && \
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip -O android-tools.zip && \
    unzip -q android-tools.zip -d $ANDROID_HOME/cmdline-tools && \
    mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest && \
    rm android-tools.zip

# 6. Tự động chấp nhận điều khoản của Google và tải bộ build-tools cho Android
RUN yes | sdkmanager --licenses && \
    sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# 7. Thiết lập đường dẫn cho Flutter SDK
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="$FLUTTER_HOME/bin:$PATH"

# 8. Kéo mã nguồn Flutter SDK bản ổn định (stable) về máy ảo
RUN git clone https://github.com/flutter/flutter.git -b stable $FLUTTER_HOME

# 9. Cấp quyền an toàn cho thư mục để tránh lỗi bảo mật của Git
RUN git config --global --add safe.directory '*'

# 10. Chạy kiểm tra môi trường để Flutter tải thêm công cụ nội bộ
RUN flutter doctor -v

# 11. Cấu hình thư mục làm việc chính
WORKDIR /app