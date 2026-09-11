#ifndef AYAGAMI_H
#define AYAGAMI_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AyagamiModel AyagamiModel;

typedef struct {
    float scale;
    float center_x;
    float center_y;
    float width;
    float height;
} AyagamiCanvas;

typedef struct {
    uint32_t texture_index;
    uint32_t vertex_count;
    uint32_t texcoord_offset;
    uint32_t index_start;
    uint32_t index_end;
    uint32_t clip_count;
    uint8_t blend_mode;
    bool culling;
    bool invert_mask;
} AyagamiArtMeshInfo;

typedef struct {
    bool visible;
    float opacity;
    float multiply_color[3];
    float screen_color[3];
    const float *vertices;
    uint32_t vertex_count;
} AyagamiArtMeshState;

AyagamiModel *ayagami_model_load(const char *model3_json_path, char *error, size_t error_size);
void ayagami_model_free(AyagamiModel *model);
AyagamiCanvas ayagami_model_canvas(const AyagamiModel *model);
uint32_t ayagami_model_texture_count(const AyagamiModel *model);
const char *ayagami_model_texture_path(const AyagamiModel *model, uint32_t index);
const uint16_t *ayagami_model_index_buffer(const AyagamiModel *model, uint32_t *count);
const float *ayagami_model_texcoord_buffer(const AyagamiModel *model, uint32_t *count);
uint32_t ayagami_model_artmesh_count(const AyagamiModel *model);
bool ayagami_model_artmesh_info(const AyagamiModel *model, uint32_t uid, AyagamiArtMeshInfo *info);
uint32_t ayagami_model_artmesh_clips(const AyagamiModel *model, uint32_t uid, uint32_t *out, uint32_t capacity);
bool ayagami_model_has_parameter(const AyagamiModel *model, const char *id);
void ayagami_model_set_parameter(AyagamiModel *model, const char *id, float value);
void ayagami_model_update(AyagamiModel *model, float dt);
uint32_t ayagami_model_draw_order(const AyagamiModel *model, uint32_t *out, uint32_t capacity);
bool ayagami_model_artmesh_state(const AyagamiModel *model, uint32_t uid, AyagamiArtMeshState *state);

#ifdef __cplusplus
}
#endif

#endif
