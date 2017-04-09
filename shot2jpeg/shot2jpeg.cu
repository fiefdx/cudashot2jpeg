// screenshot to jpeg for linux

#include <sys/time.h>

#include "shot2jpeg.h"

#define IMG_AT(x, y, i) image->data[(((y_width) + (x)) << 2) + (i)]
#define RGBA_AT(x, y, i) rgba[(((y_width) + (x)) << 2) + (i)]
#define RGB_AT(x, y, i) rgb[((y_width) + (x)) * 3 + (i)]

xcb_image_t *take_screenshot(xcb_connection_t *conn, xcb_screen_t *screen) {
    return xcb_image_get(conn,
        screen->root,
        0, 0,
        screen->width_in_pixels, screen->height_in_pixels,
        UINT32_MAX,
        XCB_IMAGE_FORMAT_Z_PIXMAP);
}

xcb_pixmap_t image_to_pixmap(xcb_connection_t *conn, xcb_screen_t *screen, xcb_image_t *image) {
    xcb_pixmap_t pixmap = xcb_generate_id(conn);
    xcb_create_pixmap(conn, 24, pixmap, screen->root, image->width, image->height);

    xcb_gcontext_t gc = xcb_generate_id(conn);
    uint32_t pixels[2] =  {screen->black_pixel, 0xffffff};
    xcb_create_gc(conn, gc, pixmap,
        XCB_GC_FOREGROUND | XCB_GC_BACKGROUND,
        pixels);

    xcb_image_put(conn, pixmap, gc, image, 0, 0, 0);

    return pixmap;
}

void get_rgba_image_data(xcb_image_t *image, uint8_t *rgba) {
    for (int y = 0; y < image->height; y++) {
        int y_width = y*image->width;
        for (int x = 0; x < image->width; x++) {
            RGBA_AT(x, y, 0) = IMG_AT(x, y, 2); // r
            RGBA_AT(x, y, 1) = IMG_AT(x, y, 1); // g
            RGBA_AT(x, y, 2) = IMG_AT(x, y, 0); // b
            RGBA_AT(x, y, 3) = IMG_AT(x, y, 3); // a
        }
    }
}

void get_rgba_image_data2(xcb_image_t *image, uint8_t *rgba) {
    memcpy(rgba, image->data, image->size);
    for (int y = 0; y < image->height; y++) {
        int y_width = y*image->width;
        for (int x = 0; x < image->width; x++) {
            RGBA_AT(x, y, 0) = IMG_AT(x, y, 2); // r
            RGBA_AT(x, y, 2) = IMG_AT(x, y, 0); // b
        }
    }
}

__global__
void get_rgba_image_data3(int n, uint8_t *data) {
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (int i = index; i < n; i += stride) {
        int x = i*4;
        uint8_t b = data[x + 2];
        data[x + 2] = data[x];
        data[x] = b;
    }
} 

void get_rgb_image_data(xcb_image_t *image, uint8_t *rgb) {
    for (int y = 0; y < image->height; y++) {
        int y_width = y*image->width;
        for (int x = 0; x < image->width; x++) {
            RGB_AT(x, y, 0) = IMG_AT(x, y, 2); // r
            RGB_AT(x, y, 1) = IMG_AT(x, y, 1); // g
            RGB_AT(x, y, 2) = IMG_AT(x, y, 0); // b
        }
    }
}

void write_to_jpeg(char *filename, int quality, xcb_image_t *image) {
    uint8_t data[image->width*image->height*4];
    get_rgba_image_data2(image, data);
    struct jpeg_compress_struct cinfo;
    struct jpeg_error_mgr jerr;
    FILE *outfile;
    JSAMPROW row_pointer[1];
    int row_stride;
    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_compress(&cinfo);
    if ((outfile = fopen(filename, "wb")) == NULL) {
        fprintf(stderr, "can't open %s\n", filename);
        exit(1);
    }
    jpeg_stdio_dest(&cinfo, outfile);

    cinfo.image_width = image->width;
    cinfo.image_height = image->height;
    cinfo.input_components = 4;
    cinfo.in_color_space = getJCS_EXT_RGBA();
    if (cinfo.in_color_space == JCS_UNKNOWN) {
        fprintf(stderr, "JCS_EXT_RGBA is not supported (probably built without libjpeg-trubo)");
        exit(1);
    }

    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, quality, TRUE);

    jpeg_start_compress(&cinfo, TRUE);

    row_stride = image->width * 4;

    while (cinfo.next_scanline < cinfo.image_height) {
        row_pointer[0] = &data[cinfo.next_scanline * row_stride];
        (void) jpeg_write_scanlines(&cinfo, row_pointer, 1);
    }

    jpeg_finish_compress(&cinfo);
    fclose(outfile);
    jpeg_destroy_compress(&cinfo);
}

void write_to_jpeg_buffer(FILE *stream, int quality, xcb_image_t *image) {
    uint8_t data[image->width*image->height*4];
    get_rgba_image_data2(image, data);
    struct jpeg_compress_struct cinfo;
    struct jpeg_error_mgr jerr;
    JSAMPROW row_pointer[1];
    int row_stride;
    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_compress(&cinfo);
    jpeg_stdio_dest(&cinfo, stream);

    cinfo.image_width = image->width;
    cinfo.image_height = image->height;
    cinfo.input_components = 4;
    cinfo.in_color_space = getJCS_EXT_RGBA();
    if (cinfo.in_color_space == JCS_UNKNOWN) {
        fprintf(stderr, "JCS_EXT_RGBA is not supported (probably built without libjpeg-trubo)");
        exit(1);
    }

    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, quality, TRUE);

    jpeg_start_compress(&cinfo, TRUE);

    row_stride = image->width * 4;

    while (cinfo.next_scanline < cinfo.image_height) {
        row_pointer[0] = &data[cinfo.next_scanline * row_stride];
        (void) jpeg_write_scanlines(&cinfo, row_pointer, 1);
    }

    jpeg_finish_compress(&cinfo);
    fclose(stream);
    jpeg_destroy_compress(&cinfo);
}

void write_to_jpeg_buffer_cuda(FILE *stream, int quality, xcb_image_t *image) {
    int N = image->width*image->height;

    struct timeval t, tt, ttt, tttt;
    gettimeofday(&t, NULL);

    uint8_t *d_data;
    uint8_t  *data;

    // cudaSetDevice(0);
    // uint8_t data[image->size];
    // cudaMallocHost(&data, image->size);
    cudaHostAlloc(&data, image->size, cudaHostAllocMapped);
    cudaMemcpy(data, image->data, image->size, cudaMemcpyHostToHost);
    // memcpy(data, image->data, image->size);
    cudaHostGetDevicePointer(&d_data, data, 0);

    cudaMalloc(&d_data, image->size);
    // cudaMemcpy(d_data, image->data, image->size, cudaMemcpyHostToDevice);

    gettimeofday(&tt, NULL);

    int blocksize = 1024;
    int blocksnum = (N + blocksize - 1)/blocksize;
    get_rgba_image_data3<<<blocksnum, blocksize>>>(N, d_data);
    cudaDeviceSynchronize();

    gettimeofday(&ttt, NULL);

    // cudaMemcpy(data, d_data, image->size, cudaMemcpyDeviceToHost);

    gettimeofday(&tttt, NULL);
    printf("cuda copy h2d: %.3fs, convert use: %.3fs, copy d2h: %.3fs\n",
            ((tt.tv_sec - t.tv_sec) * 1000000 + (tt.tv_usec - t.tv_usec))/1000000.0,
            ((ttt.tv_sec - tt.tv_sec) * 1000000 + (ttt.tv_usec - tt.tv_usec))/1000000.0,
            ((tttt.tv_sec - ttt.tv_sec) * 1000000 + (tttt.tv_usec - ttt.tv_usec))/1000000.0);

    struct jpeg_compress_struct cinfo;
    struct jpeg_error_mgr jerr;
    JSAMPROW row_pointer[1];
    int row_stride;
    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_compress(&cinfo);
    jpeg_stdio_dest(&cinfo, stream);

    cinfo.image_width = image->width;
    cinfo.image_height = image->height;
    cinfo.input_components = 4;
    cinfo.in_color_space = getJCS_EXT_RGBA();
    if (cinfo.in_color_space == JCS_UNKNOWN) {
        fprintf(stderr, "JCS_EXT_RGBA is not supported (probably built without libjpeg-trubo)");
        exit(1);
    }

    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, quality, TRUE);

    jpeg_start_compress(&cinfo, TRUE);

    row_stride = image->width * 4;

    while (cinfo.next_scanline < cinfo.image_height) {
        row_pointer[0] = &data[cinfo.next_scanline * row_stride];
        (void) jpeg_write_scanlines(&cinfo, row_pointer, 1);
    }

    jpeg_finish_compress(&cinfo);
    fclose(stream);
    jpeg_destroy_compress(&cinfo);
    cudaFree(d_data);
    cudaFreeHost(data);
}