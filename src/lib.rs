use after_effects as ae;

#[derive(Eq, PartialEq, Hash, Clone, Copy, Debug)]
enum Params {
    Left, Top, Right, Bottom,
    Link, Linked, Curve,
    InsetStart, InsetLeft, InsetTop, InsetRight, InsetBottom, InsetEnd,
}

#[derive(Default)]
struct Plugin;

ae::define_effect!(Plugin, (), Params);

unsafe extern "C" {
    fn edge_feather_render_rows(
        input: *const u8, input_stride: isize,
        output: *mut u8, output_stride: isize,
        width: i32, height: i32, y_begin: i32, y_end: i32, format: i32,
        values: *const f64, link: i32, curve: i32,
    ) -> i32;
}

fn percentage_slider() -> ae::FloatSliderDef<'static> {
    ae::FloatSliderDef::setup(|f| {
        f.set_slider_min(0.0);
        f.set_slider_max(100.0);
        f.set_valid_min(0.0);
        f.set_valid_max(100.0);
        f.set_default(0.0);
        f.set_precision(1);
        f.set_display_flags(ae::ValueDisplayFlag::PERCENT);
    })
}

fn value(params: &ae::Parameters<Params>, id: Params) -> Result<f64, ae::Error> {
    Ok(params.get(id)?.as_float_slider()?.value())
}

impl AdobePluginGlobal for Plugin {
    fn params_setup(&self, params: &mut ae::Parameters<Params>, _: InData, _: OutData) -> Result<(), Error> {
        for (id, name) in [
            (Params::Left, "Left Feather"), (Params::Top, "Top Feather"),
            (Params::Right, "Right Feather"), (Params::Bottom, "Bottom Feather"),
        ] {
            params.add(id, name, percentage_slider())?;
        }
        params.add(Params::Link, "Link Sides", ae::PopupDef::setup(|p| {
            p.set_options(&["Independent", "Top + Bottom", "Left + Right", "All Sides"]);
            p.set_default(1);
        }))?;
        params.add(Params::Linked, "Linked Feather", percentage_slider())?;
        params.add(Params::Curve, "Fade Curve", ae::PopupDef::setup(|p| {
            p.set_options(&["Smooth", "Linear"]);
            p.set_default(1);
        }))?;
        params.add_group(Params::InsetStart, Params::InsetEnd, "Edge Insets", true, |p| {
            for (id, name) in [
                (Params::InsetLeft, "Left Inset"), (Params::InsetTop, "Top Inset"),
                (Params::InsetRight, "Right Inset"), (Params::InsetBottom, "Bottom Inset"),
            ] {
                p.add(id, name, percentage_slider())?;
            }
            Ok(())
        })?;
        Ok(())
    }

    fn handle_command(&mut self, cmd: ae::Command, in_data: InData, mut out_data: OutData, params: &mut ae::Parameters<Params>) -> Result<(), ae::Error> {
        match cmd {
            ae::Command::About => {
                out_data.set_return_msg("Side Feather 0.1.0\rMathew Harwich\rIndependent four-side transparency fades.\rFeather amounts are percentages of the source width or height.");
            }
            ae::Command::GlobalSetup => {
                if in_data.is_premiere() {
                    let suite = ae::pf::suites::PixelFormat::new()?;
                    suite.clear_supported_pixel_formats(in_data.effect_ref())?;
                    // High precision first; preserve HDR RGB values without modifying color.
                    suite.add_supported_pixel_format(in_data.effect_ref(), ae::pr::PixelFormat::Bgra4444_32f)?;
                    suite.add_supported_pixel_format(in_data.effect_ref(), ae::pr::PixelFormat::Bgra4444_8u)?;
                }
            }
            ae::Command::Render { in_layer, out_layer } => {
                let width = out_layer.width();
                let height = out_layer.height();
                if width == 0 || height == 0 {
                    return Ok(());
                }
                if width != in_layer.width() || height != in_layer.height() ||
                    width > i32::MAX as usize || height > i32::MAX as usize {
                    return Err(Error::BadCallbackParameter);
                }
                let format = if in_data.is_premiere() {
                    let input_format = in_layer.pr_pixel_format()?;
                    let output_format = out_layer.pr_pixel_format()?;
                    if input_format != output_format {
                        return Err(Error::BadCallbackParameter);
                    }
                    match output_format {
                        ae::pr::PixelFormat::Bgra4444_8u => 0,
                        ae::pr::PixelFormat::Bgra4444_32f => 1,
                        _ => return Err(Error::BadCallbackParameter),
                    }
                } else {
                    match (in_layer.bit_depth(), out_layer.bit_depth()) {
                        (8, 8) => 2,
                        (16, 16) => 3,
                        _ => return Err(Error::BadCallbackParameter),
                    }
                };
                let values = [
                    value(params, Params::Left)?, value(params, Params::Top)?,
                    value(params, Params::Right)?, value(params, Params::Bottom)?,
                    value(params, Params::InsetLeft)?, value(params, Params::InsetTop)?,
                    value(params, Params::InsetRight)?, value(params, Params::InsetBottom)?,
                    value(params, Params::Linked)?,
                ];
                let link = (params.get(Params::Link)?.as_popup()?.value() - 1).clamp(0, 3);
                let curve = (params.get(Params::Curve)?.as_popup()?.value() - 1).clamp(0, 1);
                let source = unsafe { &*in_layer.as_ptr() };
                let destination = unsafe { &*out_layer.as_ptr() };
                // Process complete rows but never touch padding; check cancellation between chunks.
                for y in (0..height).step_by(64) {
                    in_data.interact().abort()?;
                    let result = unsafe {
                        edge_feather_render_rows(
                            source.data as *const u8, source.rowbytes as isize,
                            destination.data as *mut u8, destination.rowbytes as isize,
                            width as i32, height as i32,
                            y as i32, (y + 64).min(height) as i32, format,
                            values.as_ptr(), link, curve,
                        )
                    };
                    if result != 0 {
                        return Err(Error::BadCallbackParameter);
                    }
                }
            }
            _ => {}
        }
        Ok(())
    }
}
