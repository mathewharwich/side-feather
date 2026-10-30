#include "../src/FeatherCore.h"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <random>

using namespace edge_feather;

namespace {
int checks = 0;

void near(double actual, double expected, const char* message) {
    ++checks;
    if (!std::isfinite(actual) || std::abs(actual - expected) > 1e-12) {
        std::cerr << "FAIL: " << message << ": expected " << expected << ", got " << actual << '\n';
        std::exit(1);
    }
}

void bounded(double value, const char* message) {
    ++checks;
    if (!std::isfinite(value) || value < 0.0 || value > 1.0) {
        std::cerr << "FAIL: " << message << ": invalid matte " << value << '\n';
        std::exit(1);
    }
}
}  // namespace

int main() {
    Settings settings;
    Matte identity(settings, 101, 201);
    for (double x : {0.0, 50.0, 100.0}) {
        for (double y : {0.0, 100.0, 200.0}) {
            near(identity.at(x, y), 1.0, "zero settings preserve every source edge");
        }
    }
    near(identity.at(-1, 50), 0, "outside source is transparent");
    near(identity.at(101, 50), 0, "past last pixel is transparent");

    // Exercise each direction independently rather than assuming symmetric code.
    for (int side = 0; side < 4; ++side) {
        Settings isolated;
        switch (side) {
            case 0: isolated.feather.left = 20; break;
            case 1: isolated.feather.top = 20; break;
            case 2: isolated.feather.right = 20; break;
            case 3: isolated.feather.bottom = 20; break;
        }
        const Matte matte(isolated, 101, 101);
        const double boundary_x = side == 0 ? 0.0 : side == 2 ? 100.0 : 50.0;
        const double boundary_y = side == 1 ? 0.0 : side == 3 ? 100.0 : 50.0;
        const double middle_x = side == 0 ? 10.0 : side == 2 ? 90.0 : 50.0;
        const double middle_y = side == 1 ? 10.0 : side == 3 ? 90.0 : 50.0;
        near(matte.at(boundary_x, boundary_y), 0, "each enabled side is transparent at boundary");
        near(matte.at(middle_x, middle_y), 0.5, "each enabled side has its own midpoint");
        near(matte.at(100 - boundary_x, 100 - boundary_y), 1, "opposite side stays opaque");
        near(matte.at(50, 50), 1, "single edge leaves center opaque");
    }

    settings.feather.top = 25;
    Matte top(settings, 101, 101);
    near(top.at(50, 0), 0, "top fade starts transparent");
    near(top.at(50, 6.25), 0.15625, "smooth curve quarter point");
    near(top.at(50, 12.5), 0.5, "smooth curve midpoint");
    near(top.at(50, 25), 1, "top fade reaches full opacity");
    near(top.at(0, 50), 1, "top fade leaves left edge opaque");
    near(top.at(100, 50), 1, "top fade leaves right edge opaque");
    near(top.at(50, 100), 1, "top fade leaves bottom edge opaque");

    settings.curve = Curve::Linear;
    Matte linear(settings, 101, 101);
    near(linear.at(50, 6.25), 0.25, "linear curve quarter point");

    settings.feather = Sides{100, 0, 100, 0};
    Matte overlap(settings, 101, 101);
    near(overlap.at(50, 50), 0.25, "opposing broad feathers multiply");
    near(overlap.at(25, 50), 0.1875, "overlapping feathers have no discontinuity");
    near(overlap.at(0, 50), 0, "left exact edge transparent");
    near(overlap.at(100, 50), 0, "right exact edge transparent");

    settings.feather = Sides{10, 20, 30, 40};
    settings.linked_feather = 70;
    settings.link = LinkMode::TopBottom;
    auto effective = effective_feathers(settings);
    near(effective.left, 10, "top/bottom link retains left");
    near(effective.right, 30, "top/bottom link retains right");
    near(effective.top, 70, "top/bottom link sets top");
    near(effective.bottom, 70, "top/bottom link sets bottom");
    settings.link = LinkMode::LeftRight;
    effective = effective_feathers(settings);
    near(effective.left, 70, "left/right link sets left");
    near(effective.right, 70, "left/right link sets right");
    near(effective.top, 20, "left/right link retains top");
    near(effective.bottom, 40, "left/right link retains bottom");
    settings.link = LinkMode::All;
    effective = effective_feathers(settings);
    near(effective.left, 70, "all link sets left");
    near(effective.top, 70, "all link sets top");
    near(effective.right, 70, "all link sets right");
    near(effective.bottom, 70, "all link sets bottom");
    settings.link = LinkMode::Independent;
    effective = effective_feathers(settings);
    near(effective.top, 20, "unlink restores independent values");

    settings = Settings{};
    settings.feather.top = 60;
    settings.feather.left = 80;
    Matte small(settings, 101, 201);
    Matte large(settings, 1001, 2001);
    near(small.at(25, 50), large.at(250, 500), "normalized feather is resolution independent");
    near(small.horizontal(25) * small.vertical(50), small.at(25, 50),
         "separable axis masks match full matte");
    near(small.horizontal(-1), 0, "horizontal mask rejects outside coordinate");
    near(small.vertical(201), 0, "vertical mask rejects outside coordinate");

    settings = Settings{};
    settings.inset.top = 20;
    Matte hard_crop(settings, 101, 101);
    near(hard_crop.at(50, 19.999), 0, "inset removes pixels before edge");
    near(hard_crop.at(50, 20), 1, "zero feather inset has a hard opaque boundary");
    settings.feather.top = 20;
    Matte soft_crop(settings, 101, 101);
    near(soft_crop.at(50, 20), 0, "feather begins at inset boundary");
    near(soft_crop.at(50, 30), 0.5, "inset feather midpoint");
    near(soft_crop.at(50, 40), 1, "inset feather spans full source percentage");
    near(soft_crop.at(0, 60), 1, "inset top leaves other edges unchanged");
    settings.inset.bottom = 80;
    Matte collapsed(settings, 101, 101);
    near(collapsed.at(50, 20), 0, "opposite insets meeting erase rectangle");
    settings.inset.bottom = 90;
    near(Matte(settings, 101, 101).at(50, 50), 0, "crossed insets are empty");
    settings = Settings{};
    settings.inset.left = 100;
    near(Matte(settings, 101, 101).at(100, 50), 0, "100 percent inset is empty");

    settings = Settings{};
    near(Matte(settings, 1, 1).at(0, 0), 1, "singleton identity");
    settings.feather.left = 1;
    near(Matte(settings, 1, 1).at(0, 0), 0, "singleton enabled edge is transparent");
    settings = Settings{};
    settings.inset.top = 1;
    near(Matte(settings, 1, 1).at(0, 0), 0, "singleton inset consumes pixel");
    settings = Settings{};
    near(Matte(settings, 0, 100).at(0, 0), 0, "zero-sized input empty");
    near(Matte(settings, -1, 100).at(0, 0), 0, "negative-sized input empty");
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double inf = std::numeric_limits<double>::infinity();
    near(Matte(settings, inf, 100).at(0, 0), 0, "infinite dimensions rejected");
    near(Matte(settings, 100, nan).at(0, 0), 0, "NaN dimensions rejected");
    near(Matte(settings, 100, 100).at(nan, 0), 0, "NaN coordinates rejected");
    settings.feather = Sides{nan, inf, -10, -inf};
    near(Matte(settings, 101, 101).at(0, 0), 1, "invalid widths become zero");
    settings.feather = Sides{1e300, 0, 0, 0};
    settings.curve = Curve::Linear;
    near(Matte(settings, 101, 101).at(50, 50), 0.5, "huge width clamps to 100 percent");
    settings = Settings{};
    near(Matte(settings, 1e300, 1e300).at(5e299, 5e299), 1, "huge finite dimensions remain finite");

    // Rendering must never emit invalid alpha, including combinations of crossing
    // insets, broad overlapping feathers, and out-of-frame pixel coordinates.
    std::mt19937 generator(7081);
    std::uniform_real_distribution<double> percent(-100, 200);
    std::uniform_real_distribution<double> coordinate(-10, 110);
    for (int i = 0; i < 10000; ++i) {
        settings.feather = Sides{percent(generator), percent(generator), percent(generator), percent(generator)};
        settings.inset = Sides{percent(generator), percent(generator), percent(generator), percent(generator)};
        settings.linked_feather = percent(generator);
        settings.link = static_cast<LinkMode>(i % 4);
        settings.curve = (i % 2) ? Curve::Smooth : Curve::Linear;
        bounded(Matte(settings, 101, 101).at(coordinate(generator), coordinate(generator)), "random combinations remain bounded");
    }
    std::cout << "PASS: " << checks << " feather-core checks\n";
}
