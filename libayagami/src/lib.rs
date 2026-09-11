use std::ffi::{c_char, CStr, CString};
use std::fs::File;
use std::path::Path;

use ayagami::core::{ArtMesh, Item, ItemArray, Model};
use ayagami::driver::{DrawNode, Driver};
use ayagami::file::classes::BlendMode;
use ayagami::file::ParsedModel;
use ayagami::meta::{Model3, Physics3};
use ayagami::physics::{PhysicsEngine, PhysicsOptions};
use ayagami::pose::{Key, Pose};

pub struct AyagamiModel {
    model: ParsedModel,
    driver: Driver<ParsedModel>,
    physics: Option<PhysicsEngine>,
    needs_settle: bool,
    user_pose: Pose,
    physics_pose: Pose,
    draw_order: Vec<u32>,
    texture_paths: Vec<CString>,
    artmesh_clips: Vec<Vec<u32>>,
}

#[repr(C)]
pub struct AyagamiCanvas {
    scale: f32,
    center_x: f32,
    center_y: f32,
    width: f32,
    height: f32,
}

#[repr(C)]
pub struct AyagamiArtMeshInfo {
    texture_index: u32,
    vertex_count: u32,
    texcoord_offset: u32,
    index_start: u32,
    index_end: u32,
    clip_count: u32,
    blend_mode: u8,
    culling: bool,
    invert_mask: bool,
}

#[repr(C)]
pub struct AyagamiArtMeshState {
    visible: bool,
    opacity: f32,
    multiply_color: [f32; 3],
    screen_color: [f32; 3],
    vertices: *const f32,
    vertex_count: u32,
}

fn load(model3_json_path: &Path) -> Result<AyagamiModel, String> {
    let model3: Model3 = serde_json::from_reader(
        File::open(model3_json_path).map_err(|e| format!("Failed to open model3.json: {e}"))?,
    )
    .map_err(|e| format!("Failed to parse model3.json: {e}"))?;
    let base = model3_json_path.parent().unwrap_or(Path::new("."));
    let moc_path = base.join(&model3.file_references.moc);
    let mut moc_file =
        File::open(&moc_path).map_err(|e| format!("Failed to open {}: {e}", moc_path.display()))?;
    let model = ParsedModel::load(&mut moc_file).map_err(|e| format!("Failed to parse moc3: {e}"))?;
    let texture_paths = model3
        .file_references
        .textures
        .iter()
        .map(|t| CString::new(base.join(t).to_string_lossy().into_owned()).unwrap())
        .collect();
    let physics = match &model3.file_references.physics {
        Some(physics_name) => {
            let physics_path = base.join(physics_name);
            let physics_file = File::open(&physics_path)
                .map_err(|e| format!("Failed to open {}: {e}", physics_path.display()))?;
            let physics3: Physics3 = serde_json::from_reader(physics_file)
                .map_err(|e| format!("Failed to parse physics3.json: {e}"))?;
            Some(PhysicsEngine::new(physics3, PhysicsOptions::compatible(None)))
        }
        None => None,
    };
    let artmesh_clips = model
        .artmeshes()
        .into_iter()
        .map(|artmesh| artmesh.clips().into_iter().map(|clip| clip.uid()).collect())
        .collect();
    let user_pose = Pose::new(&model);
    let physics_pose = user_pose.clone();
    let driver = Driver::new(&model);
    let mut model = AyagamiModel {
        model,
        driver,
        needs_settle: physics.is_some(),
        physics,
        user_pose,
        physics_pose,
        draw_order: Vec::new(),
        texture_paths,
        artmesh_clips,
    };
    model.update(0.0);
    Ok(model)
}

impl AyagamiModel {
    fn update(&mut self, dt: f32) {
        match &mut self.physics {
            Some(physics) => {
                self.physics_pose.update(&self.user_pose);
                if self.needs_settle {
                    physics.settle(&self.physics_pose);
                    self.needs_settle = false;
                }
                physics.update(&mut self.physics_pose, dt);
                let mut pose = self.physics_pose.clone();
                pose.update(&self.user_pose);
                self.driver.set_pose(&pose);
            }
            None => self.driver.set_pose(&self.user_pose),
        }
        self.driver.drive(&self.model);
        self.draw_order.clear();
        self.collect_draw_order(None);
    }

    fn collect_draw_order(&mut self, part: Option<u32>) {
        let nodes = self.driver.draw_nodes(part).map(|nodes| nodes.to_vec()).unwrap_or_default();
        for node in nodes {
            match node {
                DrawNode::ArtMesh(uid) => self.draw_order.push(uid),
                DrawNode::OffscreenPart(uid) => self.collect_draw_order(Some(uid)),
            }
        }
    }
}

fn write_error(message: &str, error: *mut c_char, error_size: usize) {
    if error.is_null() || error_size == 0 {
        return;
    }
    let bytes = message.as_bytes();
    let length = bytes.len().min(error_size - 1);
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), error as *mut u8, length);
        *error.add(length) = 0;
    }
}

fn to_str<'a>(id: *const c_char) -> Option<&'a str> {
    if id.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(id) }.to_str().ok()
}

#[no_mangle]
pub extern "C" fn ayagami_model_load(
    model3_json_path: *const c_char,
    error: *mut c_char,
    error_size: usize,
) -> *mut AyagamiModel {
    let Some(path) = to_str(model3_json_path) else {
        write_error("Invalid path", error, error_size);
        return std::ptr::null_mut();
    };
    match load(Path::new(path)) {
        Ok(model) => Box::into_raw(Box::new(model)),
        Err(message) => {
            write_error(&message, error, error_size);
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn ayagami_model_free(model: *mut AyagamiModel) {
    if !model.is_null() {
        drop(unsafe { Box::from_raw(model) });
    }
}

#[no_mangle]
pub extern "C" fn ayagami_model_canvas(model: *const AyagamiModel) -> AyagamiCanvas {
    let model = unsafe { &*model };
    let canvas = model.model.canvas_properties();
    AyagamiCanvas {
        scale: canvas.scale,
        center_x: canvas.center.x,
        center_y: canvas.center.y,
        width: canvas.dimensions.x,
        height: canvas.dimensions.y,
    }
}

#[no_mangle]
pub extern "C" fn ayagami_model_texture_count(model: *const AyagamiModel) -> u32 {
    let model = unsafe { &*model };
    model.texture_paths.len() as u32
}

#[no_mangle]
pub extern "C" fn ayagami_model_texture_path(model: *const AyagamiModel, index: u32) -> *const c_char {
    let model = unsafe { &*model };
    match model.texture_paths.get(index as usize) {
        Some(path) => path.as_ptr(),
        None => std::ptr::null(),
    }
}

#[no_mangle]
pub extern "C" fn ayagami_model_index_buffer(model: *const AyagamiModel, count: *mut u32) -> *const u16 {
    let model = unsafe { &*model };
    let indices = model.model.index_buffer().unwrap_or(&[]);
    unsafe { *count = indices.len() as u32 };
    indices.as_ptr()
}

#[no_mangle]
pub extern "C" fn ayagami_model_texcoord_buffer(model: *const AyagamiModel, count: *mut u32) -> *const f32 {
    let model = unsafe { &*model };
    let texcoords = model.model.texcoord_buffer().unwrap_or(&[]);
    unsafe { *count = texcoords.len() as u32 };
    texcoords.as_ptr() as *const f32
}

#[no_mangle]
pub extern "C" fn ayagami_model_artmesh_count(model: *const AyagamiModel) -> u32 {
    let model = unsafe { &*model };
    model.artmesh_clips.len() as u32
}

#[no_mangle]
pub extern "C" fn ayagami_model_artmesh_info(
    model: *const AyagamiModel,
    uid: u32,
    info: *mut AyagamiArtMeshInfo,
) -> bool {
    let model = unsafe { &*model };
    let Some(artmesh) = model.model.artmeshes().index(uid as usize) else {
        return false;
    };
    let index_range = artmesh.index_range();
    let blend_mode = match artmesh.blend_config().simple() {
        Some(BlendMode::Add) => 1,
        Some(BlendMode::Multiply) => 2,
        _ => 0,
    };
    unsafe {
        *info = AyagamiArtMeshInfo {
            texture_index: artmesh.texture(),
            vertex_count: artmesh.vertex_count(),
            texcoord_offset: artmesh.texcoord_offset(),
            index_start: index_range.start,
            index_end: index_range.end,
            clip_count: model.artmesh_clips[uid as usize].len() as u32,
            blend_mode,
            culling: artmesh.culling(),
            invert_mask: artmesh.invert_mask(),
        };
    }
    true
}

#[no_mangle]
pub extern "C" fn ayagami_model_artmesh_clips(
    model: *const AyagamiModel,
    uid: u32,
    out: *mut u32,
    capacity: u32,
) -> u32 {
    let model = unsafe { &*model };
    let Some(clips) = model.artmesh_clips.get(uid as usize) else {
        return 0;
    };
    let count = clips.len().min(capacity as usize);
    unsafe { std::ptr::copy_nonoverlapping(clips.as_ptr(), out, count) };
    count as u32
}

#[no_mangle]
pub extern "C" fn ayagami_model_has_parameter(model: *const AyagamiModel, id: *const c_char) -> bool {
    let model = unsafe { &*model };
    let Some(id) = to_str(id) else {
        return false;
    };
    model.user_pose.has_key(&Key::param(id))
}

#[no_mangle]
pub extern "C" fn ayagami_model_set_parameter(model: *mut AyagamiModel, id: *const c_char, value: f32) {
    let model = unsafe { &mut *model };
    let Some(id) = to_str(id) else {
        return;
    };
    model.user_pose.set(&Key::param(id), value);
}

#[no_mangle]
pub extern "C" fn ayagami_model_update(model: *mut AyagamiModel, dt: f32) {
    let model = unsafe { &mut *model };
    model.update(dt.clamp(0.0, 0.1));
}

#[no_mangle]
pub extern "C" fn ayagami_model_draw_order(model: *const AyagamiModel, out: *mut u32, capacity: u32) -> u32 {
    let model = unsafe { &*model };
    let count = model.draw_order.len().min(capacity as usize);
    unsafe { std::ptr::copy_nonoverlapping(model.draw_order.as_ptr(), out, count) };
    count as u32
}

#[no_mangle]
pub extern "C" fn ayagami_model_artmesh_state(
    model: *const AyagamiModel,
    uid: u32,
    state: *mut AyagamiArtMeshState,
) -> bool {
    let model = unsafe { &*model };
    let Some(driven) = model.driver.artmesh_state(uid) else {
        return false;
    };
    unsafe {
        *state = AyagamiArtMeshState {
            visible: driven.visual.visible,
            opacity: driven.visual.opacity,
            multiply_color: driven.visual.multiply_color.to_array(),
            screen_color: driven.visual.screen_color.to_array(),
            vertices: driven.vertices.as_ptr() as *const f32,
            vertex_count: driven.vertices.len() as u32,
        };
    }
    true
}
