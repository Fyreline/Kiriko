//! The zero-copy Viewer target: a GPU texture Flutter samples directly (K-177).
//!
//! # In plain terms
//!
//! Normally the Viewer's picture makes a slow round trip every frame: the engine
//! draws it on the graphics card, copies it *down* into ordinary memory, hands
//! the bytes across to Flutter, and Flutter uploads them *back* onto the card to
//! show them. This module removes that round trip on Windows. The engine draws
//! into a special texture that is *shareable*: Windows can hand the same piece of
//! graphics memory to another part of the program by name (an "NT handle").
//! Flutter's Windows layer opens that handle and shows the texture on screen
//! without any copy — the picture never leaves the graphics card.
//!
//! # How it works, precisely
//!
//! wgpu runs over Direct3D 12 on Windows. We reach *through* wgpu to its D3D12
//! device (`Device::as_hal`), create a D3D12 texture in a **shared heap**
//! (`D3D12_HEAP_FLAG_SHARED`), and export an NT handle for it
//! (`ID3D12Device::CreateSharedHandle`). We then wrap that same D3D12 resource
//! back up as a `wgpu::Texture` (`create_texture_from_hal`) so the normal render
//! path can copy the finished, display-encoded frame into it. The handle is what
//! Flutter's embedder opens as a `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`
//! surface (it re-opens the shared resource on its own D3D11/ANGLE device).
//!
//! The texture is `DXGI_FORMAT_R8G8B8A8_UNORM` and holds the *already sRGB-encoded*
//! display bytes — byte-for-byte the same pixels the CPU read-back path produced,
//! so Flutter shows them identically (it treats the texture as plain RGBA8888).
//! We copy the engine's `Rgba8UnormSrgb` display texture into this `Rgba8Unorm`
//! one; wgpu allows that copy because the two formats differ only in sRGB-ness
//! (a verbatim byte copy, no re-encode).
//!
//! # Synchronisation (a known follow-up)
//!
//! After the copy we `poll(Wait)` so the GPU has finished writing before we tell
//! Flutter the frame is ready — Flutter never samples a half-written texture.
//! We render into the *same* texture each frame, so there is still a theoretical
//! race if Flutter is mid-sample when the next frame's copy begins. A keyed-mutex
//! or shared-fence handshake is the robust fix and is recorded as the follow-up
//! (K-177); it is only worth adding if tearing actually shows in practice.
//!
//! The reference for the embedder-side plumbing (descriptor shape, the DXGI
//! shared-handle surface type, the texture-registrar dance) is the MIT-licensed
//! `flutter_wgpu_texture` package; we borrow the *pattern*, not the code.

#![allow(unsafe_code)]

use crate::GpuContext;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{CloseHandle, GENERIC_ALL, HANDLE};
use windows::Win32::Graphics::Direct3D12::{
    ID3D12Device, ID3D12Resource, D3D12_HEAP_FLAG_SHARED, D3D12_HEAP_PROPERTIES,
    D3D12_HEAP_TYPE_DEFAULT, D3D12_RESOURCE_DESC, D3D12_RESOURCE_DIMENSION_TEXTURE2D,
    D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET, D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS,
    D3D12_RESOURCE_STATE_COMMON, D3D12_TEXTURE_LAYOUT_UNKNOWN,
};
use windows::Win32::Graphics::Dxgi::Common::{DXGI_FORMAT_R8G8B8A8_UNORM, DXGI_SAMPLE_DESC};

/// The wgpu-side format of the shared texture. `Rgba8Unorm` (not `…Srgb`) so the
/// display-encoded bytes are stored verbatim and Flutter reads them as plain
/// RGBA8888 — the identical pixels the read-back path produced.
const SHARED_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;

/// A D3D12 texture in a shared heap, wrapped as a `wgpu::Texture` and paired with
/// the NT handle Flutter opens. One is held for the whole Viewer session and
/// re-created only when the comp's dimensions change (a new handle is reported
/// then). Its `wgpu::Texture` keeps the underlying D3D12 resource alive, so the
/// exported handle stays valid for the texture's lifetime.
pub struct SharedTexture {
    /// The copy destination the render path writes the finished frame into.
    pub texture: wgpu::Texture,
    /// The NT handle value (`HANDLE.0 as isize`). Stored as an integer, not a
    /// `HANDLE`, so this struct stays `Send`/`Sync` — the headless renderer that
    /// owns it lives behind a process-wide lock and must remain shareable.
    handle: isize,
    pub width: u32,
    pub height: u32,
}

// The handle is an opaque OS resource identifier, not a live pointer we
// dereference; keeping it as an `isize` next to a `Send`/`Sync` `wgpu::Texture`
// makes the whole struct safely shareable across the render lock.
unsafe impl Send for SharedTexture {}
unsafe impl Sync for SharedTexture {}

impl SharedTexture {
    /// Create a `width`×`height` shared texture on `gpu`'s D3D12 device. `Err`
    /// when wgpu is not on the D3D12 backend (the shared path needs D3D12; the
    /// caller falls back to the read-back path) or any D3D12 call fails.
    pub fn new(gpu: &GpuContext, width: u32, height: u32) -> Result<Self, String> {
        let width = width.max(1);
        let height = height.max(1);

        // Reach through wgpu to the raw D3D12 device, create the shared resource
        // there, and export its NT handle — all while wgpu holds the device.
        let created = unsafe {
            gpu.device
                .as_hal::<wgpu::hal::api::Dx12, _, _>(|hal_device| {
                    let hal_device = hal_device.ok_or_else(|| {
                        "shared texture: wgpu is not running on the D3D12 backend".to_string()
                    })?;
                    create_shared_resource(hal_device.raw_device(), width, height)
                })
        };
        let (resource, handle) = created?;

        // Wrap the very same D3D12 resource as a wgpu texture so the render path
        // can copy into it. `texture_from_raw` takes a clone (a COM ref-count
        // bump); that clone, held by the returned `wgpu::Texture`, is what keeps
        // the resource — and therefore the exported handle — alive.
        let extent = wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        };
        let hal_texture = unsafe {
            wgpu::hal::dx12::Device::texture_from_raw(
                resource,
                SHARED_FORMAT,
                wgpu::TextureDimension::D2,
                extent,
                1,
                1,
            )
        };
        let texture = unsafe {
            gpu.device.create_texture_from_hal::<wgpu::hal::api::Dx12>(
                hal_texture,
                &wgpu::TextureDescriptor {
                    label: Some("lumit-shared-target"),
                    size: extent,
                    mip_level_count: 1,
                    sample_count: 1,
                    dimension: wgpu::TextureDimension::D2,
                    format: SHARED_FORMAT,
                    usage: wgpu::TextureUsages::COPY_DST,
                    view_formats: &[],
                },
            )
        };

        Ok(Self {
            texture,
            handle,
            width,
            height,
        })
    }

    /// The NT handle value Flutter opens (`kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`).
    pub fn handle(&self) -> u64 {
        self.handle as usize as u64
    }

    /// Copy the finished display texture (`Rgba8UnormSrgb`) into the shared
    /// texture and block until the GPU has finished, so the frame is complete
    /// before Flutter is told it is ready. `display` must match the shared
    /// texture's dimensions (the caller recreates on a size change).
    pub fn present(&self, gpu: &GpuContext, display: &wgpu::Texture) {
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("shared-present"),
            });
        encoder.copy_texture_to_texture(
            display.as_image_copy(),
            self.texture.as_image_copy(),
            wgpu::Extent3d {
                width: self.width,
                height: self.height,
                depth_or_array_layers: 1,
            },
        );
        gpu.queue.submit([encoder.finish()]);
        // No keyed mutex yet: wait for the write to land so a reader never sees a
        // torn frame (see the module note). Zero *CPU* pixel work still — the
        // bytes never leave the card.
        gpu.device.poll(wgpu::Maintain::Wait);
    }
}

impl Drop for SharedTexture {
    fn drop(&mut self) {
        // Release the NT handle we exported. The D3D12 resource itself is freed
        // by the `wgpu::Texture` dropping its COM reference.
        if self.handle != 0 {
            let _ = unsafe { CloseHandle(HANDLE(self.handle as *mut core::ffi::c_void)) };
        }
    }
}

/// Create a shared, simultaneous-access D3D12 texture and export its NT handle.
///
/// # Safety
/// `device` must be a valid `ID3D12Device`.
unsafe fn create_shared_resource(
    device: &ID3D12Device,
    width: u32,
    height: u32,
) -> Result<(ID3D12Resource, isize), String> {
    let heap_props = D3D12_HEAP_PROPERTIES {
        Type: D3D12_HEAP_TYPE_DEFAULT,
        ..Default::default()
    };
    let desc = D3D12_RESOURCE_DESC {
        Dimension: D3D12_RESOURCE_DIMENSION_TEXTURE2D,
        Alignment: 0,
        Width: u64::from(width),
        Height: height,
        DepthOrArraySize: 1,
        MipLevels: 1,
        Format: DXGI_FORMAT_R8G8B8A8_UNORM,
        SampleDesc: DXGI_SAMPLE_DESC {
            Count: 1,
            Quality: 0,
        },
        Layout: D3D12_TEXTURE_LAYOUT_UNKNOWN,
        // ALLOW_RENDER_TARGET keeps the format render-target-compatible (what a
        // display texture is); ALLOW_SIMULTANEOUS_ACCESS lets another device
        // (Flutter's) read it while it stays in the COMMON state, which is the
        // supported way to share a render target across APIs.
        Flags: D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET
            | D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS,
    };

    let mut resource: Option<ID3D12Resource> = None;
    device
        .CreateCommittedResource(
            &heap_props,
            D3D12_HEAP_FLAG_SHARED,
            &desc,
            D3D12_RESOURCE_STATE_COMMON,
            None,
            &mut resource,
        )
        .map_err(|e| format!("shared texture: CreateCommittedResource failed: {e}"))?;
    let resource = resource
        .ok_or_else(|| "shared texture: CreateCommittedResource returned null".to_string())?;

    let handle = device
        .CreateSharedHandle(&resource, None, GENERIC_ALL.0, PCWSTR::null())
        .map_err(|e| format!("shared texture: CreateSharedHandle failed: {e}"))?;

    Ok((resource, handle.0 as isize))
}
