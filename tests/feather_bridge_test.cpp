#include <array>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
#include <type_traits>
#include <vector>

extern "C" int edge_feather_render_rows(
    const std::uint8_t*, std::ptrdiff_t, std::uint8_t*, std::ptrdiff_t,
    int, int, int, int, int, const double*, int, int) noexcept;

namespace {
int checks = 0;
constexpr std::uint8_t sentinel = 0xcd;

void require(bool condition, const char* message) {
    ++checks;
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

template<typename T> T read(const std::uint8_t* pointer) {
    T value;
    std::memcpy(&value, pointer, sizeof(T));
    return value;
}

template<typename T> void write(std::uint8_t* pointer, T value) {
    std::memcpy(pointer, &value, sizeof(T));
}

struct World {
    int width;
    int height;
    std::size_t pixel_bytes;
    std::size_t row_bytes;
    std::ptrdiff_t stride;
    std::vector<std::uint8_t> bytes;
    // An odd guard length also exercises unaligned host-world data safely.
    static constexpr std::size_t guard = 17;

    World(int w, int h, std::size_t pixel_size, bool negative, std::size_t padding = 13)
        : width(w), height(h), pixel_bytes(pixel_size), row_bytes(w * pixel_size + padding),
          stride(static_cast<std::ptrdiff_t>(row_bytes) * (negative ? -1 : 1)),
          bytes(guard * 2 + row_bytes * h, sentinel) {}

    std::uint8_t* data() {
        return bytes.data() + guard + (stride < 0 ? row_bytes * (height - 1) : 0);
    }
    const std::uint8_t* data() const {
        return bytes.data() + guard + (stride < 0 ? row_bytes * (height - 1) : 0);
    }
    std::uint8_t* pixel(int x, int y) { return data() + y * stride + x * pixel_bytes; }
    const std::uint8_t* pixel(int x, int y) const { return data() + y * stride + x * pixel_bytes; }

    void check_padding() const {
        for (std::size_t i = 0; i < guard; ++i) {
            require(bytes[i] == sentinel, "leading guard unchanged");
            require(bytes[bytes.size() - 1 - i] == sentinel, "trailing guard unchanged");
        }
        for (int y = 0; y < height; ++y) {
            for (std::size_t i = width * pixel_bytes; i < row_bytes; ++i) {
                require(bytes[guard + y * row_bytes + i] == sentinel, "row padding untouched");
            }
        }
    }
};

template<typename T>
T scaled(T source, double matte) {
    if constexpr (std::is_floating_point_v<T>) {
        return static_cast<T>(source * matte);
    } else {
        return static_cast<T>(std::floor(source * matte + 0.5));
    }
}

template<typename T>
void top_fade(int format, bool input_negative, bool output_negative, bool in_place,
              const std::array<T, 4>& source, bool premultiplied) {
    World input(5, 5, sizeof(T) * 4, input_negative);
    World output(5, 5, sizeof(T) * 4, output_negative, 21);
    for (int y = 0; y < 5; ++y) {
        for (int x = 0; x < 5; ++x) {
            for (int c = 0; c < 4; ++c) {
                write<T>(input.pixel(x, y) + c * sizeof(T), source[c]);
            }
        }
    }
    const auto before = input.bytes;
    World& target = in_place ? input : output;
    std::array<double, 9> settings{};
    settings[1] = 100.0;  // top feather, linear across full frame
    require(edge_feather_render_rows(input.data(), input.stride, target.data(), target.stride,
                                    5, 5, 0, 5, format, settings.data(), 0, 1) == 0,
            "top-only render succeeds");
    for (int y = 0; y < 5; ++y) {
        // Live Premiere PFWorld readback established top-down adapter rows for
        // BGRA, unlike the coordinate convention of some native Premiere SDK APIs.
        const double matte = static_cast<double>(y) / 4.0;
        for (int x = 0; x < 5; ++x) {
            for (int c = 0; c < 4; ++c) {
                const bool affected = premultiplied || c == 3;
                const T expected = affected ? scaled(source[c], matte) : source[c];
                const T actual = read<T>(target.pixel(x, y) + c * sizeof(T));
                require(actual == expected, "format alpha, color and top-down orientation correct");
                if (!affected) {
                    require(std::memcmp(target.pixel(x, y) + c * sizeof(T),
                                        &source[c], sizeof(T)) == 0,
                            "straight RGB bits remain unchanged including HDR");
                }
            }
        }
    }
    if (!in_place) require(input.bytes == before, "out-of-place source unchanged");
    input.check_padding();
    target.check_padding();
}

void identity(int format, std::size_t pixel_size, bool negative, bool in_place) {
    World input(7, 3, pixel_size, negative);
    World output(7, 3, pixel_size, !negative, 11);
    for (int y = 0; y < 3; ++y) {
        for (int x = 0; x < 7; ++x) {
            for (std::size_t i = 0; i < pixel_size; ++i) {
                input.pixel(x, y)[i] = static_cast<std::uint8_t>((y * 37 + x * 23 + i * 61) % 256);
            }
        }
    }
    const auto before = input.bytes;
    World& target = in_place ? input : output;
    std::array<double, 9> settings{};
    require(edge_feather_render_rows(input.data(), input.stride, target.data(), target.stride,
                                    7, 3, 0, 3, format, settings.data(), 0, 0) == 0,
            "identity render succeeds");
    if (in_place) {
        require(input.bytes == before, "in-place identity preserves every byte");
    } else {
        for (int y = 0; y < 3; ++y) {
            require(std::memcmp(input.pixel(0, y), target.pixel(0, y), 7 * pixel_size) == 0,
                    "default effect is bit identity in every format");
        }
        require(input.bytes == before, "identity does not change input");
    }
    target.check_padding();
}

void row_chunks_and_link() {
    World input(5, 5, 4, false);
    World output(5, 5, 4, false);
    for (int y = 0; y < 5; ++y) {
        for (int x = 0; x < 5; ++x) {
            for (int c = 0; c < 4; ++c) input.pixel(x, y)[c] = 200;
        }
    }
    std::array<double, 9> settings{};
    settings[8] = 50;
    require(edge_feather_render_rows(input.data(), input.stride, output.data(), output.stride,
                                    5, 5, 1, 4, 0, settings.data(), 1, 1) == 0,
            "chunked linked render succeeds");
    require(output.pixel(2, 0)[3] == sentinel && output.pixel(2, 4)[3] == sentinel,
            "rows outside requested chunk untouched");
    require(output.pixel(2, 1)[3] == 100, "linked top alpha multiplies existing alpha");
    require(output.pixel(2, 2)[3] == 200, "linked center remains opaque relative to source");
    require(output.pixel(2, 3)[3] == 100, "linked bottom alpha multiplies existing alpha");
    require(output.pixel(0, 2)[3] == 200 && output.pixel(4, 2)[3] == 200,
            "top/bottom link retains inactive left/right sides");
    output.check_padding();
}

void invalid_inputs() {
    World input(5, 5, 4, false);
    World output(5, 5, 4, false);
    std::array<double, 9> settings{};
    const auto before = output.bytes;
    for (int format : {-1, 4, 99}) {
        require(edge_feather_render_rows(input.data(), input.stride, output.data(), output.stride,
                                        5, 5, 0, 5, format, settings.data(), 0, 0) != 0,
                "unknown pixel format rejected");
    }
    require(edge_feather_render_rows(nullptr, input.stride, output.data(), output.stride,
                                    5, 5, 0, 5, 0, settings.data(), 0, 0) != 0,
            "null source rejected");
    require(edge_feather_render_rows(input.data(), input.stride, nullptr, output.stride,
                                    5, 5, 0, 5, 0, settings.data(), 0, 0) != 0,
            "null destination rejected");
    require(edge_feather_render_rows(input.data(), input.stride, output.data(), output.stride,
                                    5, 5, 0, 5, 0, nullptr, 0, 0) != 0,
            "null parameters rejected");
    require(edge_feather_render_rows(input.data(), 19, output.data(), output.stride,
                                    5, 5, 0, 5, 0, settings.data(), 0, 0) != 0,
            "source stride smaller than pixel row rejected");
    require(edge_feather_render_rows(input.data(), input.stride, output.data(), -19,
                                    5, 5, 0, 5, 0, settings.data(), 0, 0) != 0,
            "negative destination stride smaller than row rejected");
    require(edge_feather_render_rows(input.data(), std::numeric_limits<std::ptrdiff_t>::min(),
                                    output.data(), output.stride,
                                    5, 5, 0, 5, 0, settings.data(), 0, 0) != 0,
            "minimum signed source stride rejected before abs overflow");
    require(edge_feather_render_rows(input.data(), input.stride, output.data(),
                                    std::numeric_limits<std::ptrdiff_t>::min(),
                                    5, 5, 0, 5, 0, settings.data(), 0, 0) != 0,
            "minimum signed destination stride rejected before abs overflow");
    require(edge_feather_render_rows(input.data(), input.stride, output.data(), output.stride,
                                    5, 5, -1, 5, 0, settings.data(), 0, 0) != 0,
            "negative starting row rejected");
    require(edge_feather_render_rows(input.data(), input.stride, output.data(), output.stride,
                                    5, 5, 0, 6, 0, settings.data(), 0, 0) != 0,
            "past-end row rejected");
    require(edge_feather_render_rows(input.data(), input.stride, output.data(), output.stride,
                                    5, 5, 4, 2, 0, settings.data(), 0, 0) != 0,
            "reversed row interval rejected");
    require(edge_feather_render_rows(input.data(), input.stride, output.data(), output.stride,
                                    0, 5, 0, 5, 0, settings.data(), 0, 0) != 0,
            "zero width rejected");
    require(output.bytes == before, "invalid calls never mutate output");
}

void benchmark(int width, int height) {
    const std::ptrdiff_t stride = static_cast<std::ptrdiff_t>(width) * 4;
    std::vector<std::uint8_t> input(stride * height, 255);
    std::vector<std::uint8_t> output(stride * height, 0);
    std::array<double, 9> settings{40, 40, 40, 40, 0, 0, 0, 0, 0};
    const auto begin = std::chrono::steady_clock::now();
    const int status = edge_feather_render_rows(input.data(), stride, output.data(), stride,
                                                width, height, 0, height, 0, settings.data(), 0, 0);
    const auto end = std::chrono::steady_clock::now();
    require(status == 0, "benchmark render succeeds");
    // Touch output so the exercise remains observable to optimizing builds.
    require(output[3] == 0 && output[(height / 2) * stride + (width / 2) * 4 + 3] == 255,
            "benchmark output has transparent corner and opaque center");
    const double ms = std::chrono::duration<double, std::milli>(end - begin).count();
    std::cout << "CPU single-call " << width << 'x' << height << ": "
              << std::fixed << std::setprecision(2) << ms << " ms\n";
}
}  // namespace

int main() {
    for (bool input_negative : {false, true}) {
        for (bool output_negative : {false, true}) {
            top_fade<std::uint8_t>(0, input_negative, output_negative, false, {17, 45, 201, 128}, false);
            top_fade<float>(1, input_negative, output_negative, false, {-0.25f, 2.5f, 100.125f, 0.8f}, false);
            top_fade<std::uint8_t>(2, input_negative, output_negative, false, {128, 64, 32, 16}, true);
            top_fade<std::uint16_t>(3, input_negative, output_negative, false, {32768, 16384, 8192, 4096}, true);
        }
        top_fade<std::uint8_t>(0, input_negative, false, true, {17, 45, 201, 128}, false);
        top_fade<float>(1, input_negative, false, true, {-0.25f, 2.5f, 100.125f, 0.8f}, false);
        top_fade<std::uint8_t>(2, input_negative, false, true, {128, 64, 32, 16}, true);
        top_fade<std::uint16_t>(3, input_negative, false, true, {32768, 16384, 8192, 4096}, true);
        for (int format = 0; format < 4; ++format) {
            const std::size_t size = format == 1 ? 16 : format == 3 ? 8 : 4;
            identity(format, size, input_negative, false);
            identity(format, size, input_negative, true);
        }
    }
    row_chunks_and_link();
    invalid_inputs();
    benchmark(1920, 1080);
    benchmark(3840, 2160);
    std::cout << "PASS: " << checks << " feather-bridge checks\n";
}
