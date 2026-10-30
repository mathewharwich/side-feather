#include "FeatherCore.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <new>
#include <limits>
#include <type_traits>

namespace {

// All byte access uses memcpy so no alignment assumption is imposed on host worlds.
template<typename T>
T read_channel(const std::uint8_t* p) noexcept {
    T value;
    std::memcpy(&value, p, sizeof(T));
    return value;
}

template<typename T>
void write_channel(std::uint8_t* p, T value) noexcept {
    std::memcpy(p, &value, sizeof(T));
}

template<typename T>
T scaled(T value, double matte) noexcept {
    if constexpr (std::is_floating_point_v<T>) {
        return static_cast<T>(value * matte);
    } else {
        return static_cast<T>(std::floor(value * matte + 0.5));
    }
}

template<typename T>
void render_row(const std::uint8_t* input, std::uint8_t* output,
                int width, const double* horizontal, double vertical,
                bool premultiplied, int alpha_channel) noexcept {
    for (int x = 0; x < width; ++x) {
        const auto* src = input + x * 4 * sizeof(T);
        auto* dst = output + x * 4 * sizeof(T);
        const double mask = horizontal[x] * vertical;
        // Preserve exact source bits at identity, including HDR/out-of-range colors.
        if (mask == 1.0) {
            std::memcpy(dst, src, 4 * sizeof(T));
            continue;
        }
        for (int channel = 0; channel < 4; ++channel) {
            const T value = read_channel<T>(src + channel * sizeof(T));
            write_channel<T>(dst + channel * sizeof(T),
                premultiplied || channel == alpha_channel ? scaled(value, mask) : value);
        }
    }
}

} // namespace

// values: left/top/right/bottom feather; four insets; linked feather.
// format: 0=Premiere straight BGRA8, 1=Premiere straight BGRA32f,
//         2=AE premult ARGB8, 3=AE premult ARGB16.
// Premiere's AE-compatible PFWorld adapter is top-down, confirmed with a top-only
// fade rendered in Premiere Pro 26.5.2. The lower-left convention documented for
// native Premiere buffers does not describe the PFWorld buffers supplied here.
// Strides remain signed and are applied from the original host-provided data pointer.
extern "C" int edge_feather_render_rows(
    const std::uint8_t* input, std::ptrdiff_t input_stride,
    std::uint8_t* output, std::ptrdiff_t output_stride,
    int width, int height, int y_begin, int y_end, int format,
    const double* values, int link, int curve) noexcept {
    if (!input || !output || !values || width <= 0 || height <= 0 ||
        y_begin < 0 || y_end > height || y_begin > y_end || format < 0 || format > 3) {
        return 1;
    }
    const std::ptrdiff_t pixel_size = format == 1 ? 16 : format == 3 ? 8 : 4;
    if (input_stride == std::numeric_limits<std::ptrdiff_t>::min() ||
        output_stride == std::numeric_limits<std::ptrdiff_t>::min() ||
        std::abs(input_stride) < width * pixel_size ||
        std::abs(output_stride) < width * pixel_size) {
        return 1;
    }
    edge_feather::Settings settings;
    settings.feather = {values[0], values[1], values[2], values[3]};
    settings.inset = {values[4], values[5], values[6], values[7]};
    settings.linked_feather = values[8];
    settings.link = static_cast<edge_feather::LinkMode>(link);
    settings.curve = static_cast<edge_feather::Curve>(curve);
    const edge_feather::Matte matte(settings, width, height);
    // The matte is separable: evaluate horizontal ramps once, vertical ramps once
    // per row, and perform just one multiply per pixel in the inner loop.
    std::unique_ptr<double[]> horizontal(new (std::nothrow) double[width]);
    if (!horizontal) {
        return 1;
    }
    for (int x = 0; x < width; ++x) {
        horizontal[x] = matte.horizontal(x);
    }
    for (int row = y_begin; row < y_end; ++row) {
        const auto* src = input + row * input_stride;
        auto* dst = output + row * output_stride;
        const double vertical = matte.vertical(row);
        switch (format) {
            case 0: render_row<std::uint8_t>(src, dst, width, horizontal.get(), vertical, false, 3); break;
            case 1: render_row<float>(src, dst, width, horizontal.get(), vertical, false, 3); break;
            case 2: render_row<std::uint8_t>(src, dst, width, horizontal.get(), vertical, true, 0); break;
            case 3: render_row<std::uint16_t>(src, dst, width, horizontal.get(), vertical, true, 0); break;
        }
    }
    return 0;
}
