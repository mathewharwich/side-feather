#pragma once

#include <algorithm>
#include <cmath>

namespace edge_feather {

enum class LinkMode { Independent = 0, TopBottom = 1, LeftRight = 2, All = 3 };
enum class Curve { Smooth = 0, Linear = 1 };

// Percentages of the full source span, not the remaining inset rectangle.
struct Sides {
    double left = 0.0;
    double top = 0.0;
    double right = 0.0;
    double bottom = 0.0;
};

struct Settings {
    Sides feather;
    Sides inset;
    LinkMode link = LinkMode::Independent;
    double linked_feather = 0.0;
    Curve curve = Curve::Smooth;
};

inline double percentage(double value) noexcept {
    // Invalid host values should not produce NaNs or unexpectedly erase a clip.
    return std::isfinite(value) ? std::clamp(value, 0.0, 100.0) : 0.0;
}

inline Sides effective_feathers(const Settings& settings) noexcept {
    Sides result{percentage(settings.feather.left), percentage(settings.feather.top),
                 percentage(settings.feather.right), percentage(settings.feather.bottom)};
    const double linked = percentage(settings.linked_feather);
    switch (settings.link) {
        case LinkMode::TopBottom:
            result.top = result.bottom = linked;
            break;
        case LinkMode::LeftRight:
            result.left = result.right = linked;
            break;
        case LinkMode::All:
            result = Sides{linked, linked, linked, linked};
            break;
        case LinkMode::Independent:
        default:
            break;
    }
    return result;
}

// Prepare once per rendered frame, then evaluate at source pixel-center coordinates.
// The first pixel is (0,0), the last is (width-1,height-1). This convention keeps
// the outermost affected pixel transparent and the fade stable across resolutions.
// Multiply the incoming premultiplied RGB AND alpha by the returned matte.
class Matte {
public:
    Matte(const Settings& settings, double width, double height) noexcept
        : smooth_(settings.curve != Curve::Linear) {
        if (!std::isfinite(width) || !std::isfinite(height) || width < 1.0 || height < 1.0) {
            return;
        }

        const double span_x = width - 1.0;
        const double span_y = height - 1.0;
        const Sides inset{percentage(settings.inset.left), percentage(settings.inset.top),
                          percentage(settings.inset.right), percentage(settings.inset.bottom)};
        if (inset.left + inset.right >= 100.0 || inset.top + inset.bottom >= 100.0) {
            return;
        }
        // A positive inset consumes a singleton axis completely.
        if ((span_x == 0.0 && inset.left + inset.right > 0.0) ||
            (span_y == 0.0 && inset.top + inset.bottom > 0.0)) {
            return;
        }

        left_ = span_x * (inset.left / 100.0);
        top_ = span_y * (inset.top / 100.0);
        right_ = span_x * (1.0 - inset.right / 100.0);
        bottom_ = span_y * (1.0 - inset.bottom / 100.0);

        const Sides feather = effective_feathers(settings);
        // Keep an enabled feather meaningful even on a one-pixel axis.
        const double scale_x = std::max(span_x, 1.0) / 100.0;
        const double scale_y = std::max(span_y, 1.0) / 100.0;
        feather_ = Sides{feather.left * scale_x, feather.top * scale_y,
                         feather.right * scale_x, feather.bottom * scale_y};
        valid_ = true;
    }

    double at(double x, double y) const noexcept {
        return horizontal(x) * vertical(y);
    }

    // Separable axis masks let renderers cache one horizontal row and compute
    // the vertical contribution once per row instead of once per pixel.
    double horizontal(double x) const noexcept {
        if (!valid_ || !std::isfinite(x) || x < left_ || x > right_) {
            return 0.0;
        }
        return ramp(x - left_, feather_.left) * ramp(right_ - x, feather_.right);
    }

    double vertical(double y) const noexcept {
        if (!valid_ || !std::isfinite(y) || y < top_ || y > bottom_) {
            return 0.0;
        }
        return ramp(y - top_, feather_.top) * ramp(bottom_ - y, feather_.bottom);
    }

private:
    double ramp(double distance, double feather) const noexcept {
        if (feather <= 0.0) {
            return 1.0;
        }
        const double t = std::clamp(distance / feather, 0.0, 1.0);
        return smooth_ ? t * t * (3.0 - 2.0 * t) : t;
    }

    Sides feather_;
    double left_ = 0.0;
    double top_ = 0.0;
    double right_ = 0.0;
    double bottom_ = 0.0;
    bool valid_ = false;
    bool smooth_ = true;
};

}  // namespace edge_feather
