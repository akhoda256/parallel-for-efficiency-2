#include "config.h"
#include "custom_types.h"
#include "dct8x8_block.h"
#include "xml_aux.h"
#include <iostream>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <sys/time.h>
#include <tiff.h>
#include <tiffio.h>
#include <vector>
#include <cuda_runtime.h>
#include <unistd.h>
#include <omp.h>
#include <immintrin.h>

using namespace std;

float *d_inputR, *d_inputG, *d_inputB, *d_outputY, *d_outputCb, *d_outputCr;
float *h_inputR, *h_inputG, *h_inputB, *h_outputY, *h_outputCb, *h_outputCr;

//__global__ void convertRGBtoYCbCrKernel(float *inputR, float *inputG, float *inputB, float *outputY,
//                                        float *outputCb, float *outputCr, int width, int height) {
//    int x = blockIdx.x * blockDim.x + threadIdx.x;
//    int y = blockIdx.y * blockDim.y + threadIdx.y;
//
//    if (x < width && y < height) {
//        int index = x * width + y;
//        float R = inputR[index];
//        float G = inputG[index];
//        float B = inputB[index];
//
//        float Y = 0 + 0.299f * R + 0.587f * G + 0.113f * B;
//        float Cb = 128 - 0.168736f * R - 0.331264f * G + 0.5f * B;
//        float Cr = 128 + 0.5f * R - 0.418688f * G - 0.081312f * B;
//
//        outputY[index] = Y;
//        outputCb[index] = Cb;
//        outputCr[index] = Cr;
//    }
//}

__global__ void convertRGBtoYCbCrKernel(float *inputR1, float *inputG1, float *inputB1, float *outputY1,
                                        float *outputCb1, float *outputCr1, int size, int offset) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x + offset;

    if (idx < size) {
        float R = inputR1[idx];
        float G = inputG1[idx];
        float B = inputB1[idx];

        float Y = 0 + 0.299f * R + 0.587f * G + 0.113f * B;
        float Cb = 128 - 0.168736f * R - 0.331264f * G + 0.5f * B;
        float Cr = 128 + 0.5f * R - 0.418688f * G - 0.081312f * B;

        outputY1[idx] = Y;
        outputCb1[idx] = Cb;
        outputCr1[idx] = Cr;
    }
}

__global__ void convertRGBtoYCbCrKernel1(float *inputR, float *inputG, float *inputB, float *outputY,
                                        float *outputCb, float *outputCr, int size, int offset) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x + offset;

    if (idx < size) {
        float R = inputR[idx];
        float G = inputG[idx];
        float B = inputB[idx];

        float Y = 0 + 0.299f * R + 0.587f * G + 0.113f * B;


        outputY[idx] = Y;
    }
}

__global__ void convertRGBtoYCbCrKernel2(float *inputR, float *inputG, float *inputB, float *outputY,
                                        float *outputCb, float *outputCr, int size, int offset) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x + offset;

    if (idx < size) {
        float R = inputR[idx];
        float G = inputG[idx];
        float B = inputB[idx];

        float Cb = 128 - 0.168736f * R - 0.331264f * G + 0.5f * B;

        outputCb[idx] = Cb;
    }
}

__global__ void convertRGBtoYCbCrKernel3(float *inputR, float *inputG, float *inputB, float *outputY,
                                        float *outputCb, float *outputCr, int size, int offset) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x + offset;

    if (idx < size) {
        float R = inputR[idx];
        float G = inputG[idx];
        float B = inputB[idx];


        float Cr = 128 + 0.5f * R - 0.418688f * G - 0.081312f * B;

        outputCr[idx] = Cr;
    }
}

void
loadImage (int number, string path, Image **photo)
{
  string filename;
  TIFFRGBAImage img;
  char emsg[1024];

  filename = path + to_string (number) + ".tiff";
  TIFF *tif = TIFFOpen (filename.c_str (), "r");
  if (tif == NULL)
    fprintf (stderr, "Failed opening image: %s\n", filename.c_str ());
  if (!(TIFFRGBAImageBegin (&img, tif, 0, emsg)))
    TIFFError (filename.c_str (), "%s", emsg);

  uint32_t w, h;
  size_t npixels;
  uint32_t *raster;

  TIFFGetField (tif, TIFFTAG_IMAGEWIDTH, &w);
  TIFFGetField (tif, TIFFTAG_IMAGELENGTH, &h);
  npixels = w * h;
  raster = (uint32_t *)_TIFFmalloc (npixels * sizeof (uint32_t));

  TIFFReadRGBAImage (tif, w, h, raster, 0);

  if (*photo == NULL)
    *photo = new Image ((int)w, (int)h, FULLSIZE);

  // Matlab and LibTIFF store the image diferently.
  // Necessary to mirror the image horizonatly to be consistent
  for (int j = 0; j < (int)w; j++)
    {
      for (int i = 0; i < (int)h; i++)
        {
          // The inversion is ON PURPOSE
          (*photo)->rc->data[(h - 1 - i) * w + j]
              = (float)TIFFGetR (raster[i * w + j]);
          (*photo)->gc->data[(h - 1 - i) * w + j]
              = (float)TIFFGetG (raster[i * w + j]);
          (*photo)->bc->data[(h - 1 - i) * w + j]
              = (float)TIFFGetB (raster[i * w + j]);
        }
    }

  _TIFFfree (raster);
  TIFFRGBAImageEnd (&img);
  TIFFClose (tif);
}

void
convertRGBtoYCbCr_original (Image *in, Image *out)
{
    int width = in->width;
    int height = in->height;

    for (int y = 0; y < width; y++)
    {
        for (int x = 0; x < height; x++)
        {

            float R = in->rc->data[x * width + y];
            float G = in->gc->data[x * width + y];
            float B = in->bc->data[x * width + y];
            float Y = 0 + ((float)0.299 * R) + ((float)0.587 * G)
                      + ((float)0.113 * B);
            float Cb = 128 - ((float)0.168736 * R) - ((float)0.331264 * G)
                       + ((float)0.5 * B);
            float Cr = 128 + ((float)0.5 * R) - ((float)0.418688 * G)
                       - ((float)0.081312 * B);
            out->rc->data[x * width + y] = Y;
            out->gc->data[x * width + y] = Cb;
            out->bc->data[x * width + y] = Cr;
        }
    }

    // return out;
}

void initGPU(int width, int height){
    int size = width * height;
    int sizeByte = size * sizeof(float);
    struct timeval starttime, endtime;
    //initGPU(width, height);
    gettimeofday (&starttime, NULL);
    cudaMalloc((void**)&d_inputR, sizeByte);
    cudaMalloc((void**)&d_inputG, sizeByte);
    cudaMalloc((void**)&d_inputB, sizeByte);

    cudaHostAlloc((void**)&h_inputR, sizeByte, cudaHostAllocDefault);
    cudaHostAlloc((void**)&h_inputG, sizeByte, cudaHostAllocDefault);
    cudaHostAlloc((void**)&h_inputB, sizeByte, cudaHostAllocDefault);

    cudaMalloc((void**)&d_outputY, sizeByte);
    cudaMalloc((void**)&d_outputCb, sizeByte);
    cudaMalloc((void**)&d_outputCr, sizeByte);

    cudaHostAlloc((void**)&h_outputY, sizeByte, cudaHostAllocDefault);
    cudaHostAlloc((void**)&h_outputCb, sizeByte, cudaHostAllocDefault);
    cudaHostAlloc((void**)&h_outputCr, sizeByte, cudaHostAllocDefault);

//    dim3 blockSize(16);
//    dim3 gridSize(1); // Adjust block sizeByte as needed
//    convertRGBtoYCbCrKernel1<<<gridSize, blockSize>>>(d_inputR, d_inputG, d_inputB, d_outputY, d_outputCb, d_outputCr, size, 0);
//    convertRGBtoYCbCrKernel2<<<gridSize, blockSize>>>(d_inputR, d_inputG, d_inputB, d_outputY, d_outputCb, d_outputCr, size, 0);
//    convertRGBtoYCbCrKernel3<<<gridSize, blockSize>>>(d_inputR, d_inputG, d_inputB, d_outputY, d_outputCb, d_outputCr, size, 0);
    gettimeofday (&endtime, NULL);
    double diff = double (endtime.tv_sec) * 1000.0f
           + double (endtime.tv_usec) / 1000.0f
           - double (starttime.tv_sec) * 1000.0f
           - double (starttime.tv_usec) / 1000.0f; // in ms
    cout<<"initGpu = "<<diff<<endl;
}


void freeGpu(){
    struct timeval starttime, endtime;
    //initGPU(width, height);
    gettimeofday (&starttime, NULL);
    cudaFreeHost(h_inputR);
    cudaFreeHost(h_inputB);
    cudaFreeHost(h_inputG);
    cudaFreeHost(h_outputY);
    cudaFreeHost(h_outputCr);
    cudaFreeHost(h_outputCb);

    cudaFree(d_inputR);
    cudaFree(d_inputG);
    cudaFree(d_inputB);
    cudaFree(d_outputY);
    cudaFree(d_outputCb);
    cudaFree(d_outputCr);
    gettimeofday (&endtime, NULL);
    double diff = double (endtime.tv_sec) * 1000.0f
                  + double (endtime.tv_usec) / 1000.0f
                  - double (starttime.tv_sec) * 1000.0f
                  - double (starttime.tv_usec) / 1000.0f; // in ms
    cout<<"freeGPU = "<<diff<<endl;
}


void memcpy_avx2(void* dest, const void* src, size_t size) {
    // Ensure size is a multiple of 32 (256 bits)
    size_t aligned_size = size & ~0x1F;

    // Cast the source and destination pointers to the appropriate type
    __m256i* dest_ptr = (__m256i*)dest;
    const __m256i* src_ptr = (const __m256i*)src;

    // Copy data in 256-bit (32-byte) chunks
    for (size_t i = 0; i < aligned_size / 32; i++) {
        __m256i data = _mm256_loadu_si256(src_ptr + i);  // Load 256 bits from src
        _mm256_storeu_si256(dest_ptr + i, data);         // Store 256 bits to dest
    }

    // Copy any remaining bytes (less than 32 bytes)
    size_t remaining_size = size - aligned_size;
    if (remaining_size > 0) {
        char* dest_tail = (char*)dest + aligned_size;
        const char* src_tail = (const char*)src + aligned_size;
        for (size_t i = 0; i < remaining_size; i++) {
            dest_tail[i] = src_tail[i];
        }
    }
}

void
convertRGBtoYCbCr1 (Image *in, Image *out){
    int width = in->width;
    int height = in->height;
    int size = width * height;
    int sizeByte = width * height * sizeof(float);

    float *d_inputR1, *d_inputG1, *d_inputB1, *d_outputY1, *d_outputCb1, *d_outputCr1;


    cudaMalloc((void**)&d_inputR1, sizeByte);
    cudaMalloc((void**)&d_inputG1, sizeByte);
    cudaMalloc((void**)&d_inputB1, sizeByte);
    cudaMalloc((void**)&d_outputY1, sizeByte);
    cudaMalloc((void**)&d_outputCb1, sizeByte);
    cudaMalloc((void**)&d_outputCr1, sizeByte);

    cudaMemcpy(d_inputR1, in->rc->data, width * height * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_inputG1, in->gc->data, width * height * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_inputB1, in->bc->data, width * height * sizeof(float), cudaMemcpyHostToDevice);


    dim3 blockSize(128);
    dim3 gridSize(size / blockSize.x); // Adjust block sizeByte as needed
    convertRGBtoYCbCrKernel<<<gridSize, blockSize>>>(d_inputR1, d_inputG1, d_inputB1, d_outputY1, d_outputCb1, d_outputCr1, size, 0);

    cudaMemcpy(out->rc->data, d_outputY1, width * height * sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(out->gc->data, d_outputCb1, width * height * sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(out->bc->data, d_outputCr1, width * height * sizeof(float), cudaMemcpyDeviceToHost);

    cudaFree(d_inputR1);
    cudaFree(d_inputG1);
    cudaFree(d_inputB1);
    cudaFree(d_outputY1);
    cudaFree(d_outputCb1);
    cudaFree(d_outputCr1);

}

void
convertRGBtoYCbCr2 (Image *in, Image *out){
    int width = in->width;
    int height = in->height;
    int size = width * height;
    int sizeByte = width * height * sizeof(float);


    memcpy(h_inputR, in->rc->data, sizeByte);
    memcpy(h_inputG, in->gc->data, sizeByte);
    memcpy(h_inputB, in->bc->data, sizeByte);

    cudaMemcpy(d_inputR, h_inputB, width * height * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_inputG, h_inputG, width * height * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_inputB, h_inputB, width * height * sizeof(float), cudaMemcpyHostToDevice);


    dim3 blockSize(128);
    dim3 gridSize(size / blockSize.x); // Adjust block sizeByte as needed
    convertRGBtoYCbCrKernel<<<gridSize, blockSize>>>(d_inputR, d_inputG, d_inputB, d_outputY, d_outputCb, d_outputCr, size, 0);

    cudaMemcpy(h_outputY, d_outputY, width * height * sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(h_outputCb, d_outputCb, width * height * sizeof(float), cudaMemcpyDeviceToHost);
    cudaMemcpy(h_outputCr, d_outputCr, width * height * sizeof(float), cudaMemcpyDeviceToHost);


    memcpy(out->rc->data, h_outputY, sizeByte);
    memcpy(out->gc->data, h_outputCb, sizeByte);
    memcpy(out->bc->data, h_outputCr, sizeByte);

}


void
convertRGBtoYCbCr (Image *in, Image *out)
{
    int width = in->width;
    int height = in->height;
    int size = width * height;
    int sizeByte = width * height * sizeof(float);
    // Allocate device memory for input and output data
//    struct timeval starttime, endtime;
//    //initGPU(width, height);
//    gettimeofday (&starttime, NULL);
    int numChunks = 32;
    #pragma omp parallel for num_threads(4)
    for(int i = 0; i <  numChunks; i++){
        int offset = i*(size/numChunks);
        //cout<<omp_get_thread_num()<<endl;
        memcpy(&h_inputR[offset] , &(in->rc->data[offset]), sizeByte/numChunks);
//        memcpy(&h_inputG[offset] , &(in->gc->data[offset]), sizeByte/numChunks);
//        memcpy(&h_inputB[offset] , &(in->bc->data[offset]), sizeByte/numChunks);
    }
    #pragma omp parallel for num_threads(4)
    for(int i = 0; i <  numChunks; i++){
        int offset = i*(size/numChunks);
        memcpy(&h_inputG[offset] , &(in->gc->data[offset]), sizeByte/numChunks);
    }
    #pragma omp parallel for num_threads(4)
    for(int i = 0; i <  numChunks; i++){
        int offset = i*(size/numChunks);
        //cout<<omp_get_thread_num()<<endl;
        memcpy(&h_inputB[offset] , &(in->bc->data[offset]), sizeByte/numChunks);
    }

//    gettimeofday (&endtime, NULL);
//    double diff = double (endtime.tv_sec) * 1000.0f
//                 + double (endtime.tv_usec) / 1000.0f
//                 - double (starttime.tv_sec) * 1000.0f
//                 - double (starttime.tv_usec) / 1000.0f; // in ms
//                 cout<<"val = "<<diff<<endl;

//    cudaEvent_t start, end;
//    cudaEventCreate(&start);
//    cudaEventCreate(&end);
//
//    cudaEventRecord(start);
//    gettimeofday(&starttime, NULL);
    // Create CUDA stream for asynchronous operations
    int numStreams = 16;
    cudaStream_t streams[numStreams];
    for (int i = 0; i < numStreams; i++) {
        cudaStreamCreate(&streams[i]);
    }

    // Use the streams for asynchronous operations



// Start asynchronous memory copies
    dim3 blockSize(128);
    dim3 gridSize(size / (blockSize.x * numStreams)); // Adjust block sizeByte as needed
    for (int i = 0; i < numStreams; i++) {
        int offset = i * size/numStreams;
        cudaMemcpyAsync(&d_inputR[offset], &h_inputR[offset], sizeByte / numStreams, cudaMemcpyHostToDevice, streams[i]);
        cudaError_t cudaStatus = cudaGetLastError();
        if (cudaStatus != cudaSuccess) {
            fprintf(stderr, "Kernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
            // Additional error handling here, such as cleaning up resources
        }
        cudaMemcpyAsync(&d_inputG[offset], &h_inputG[offset], sizeByte / numStreams, cudaMemcpyHostToDevice, streams[i]);
        cudaMemcpyAsync(&d_inputB[offset], &h_inputB[offset], sizeByte / numStreams, cudaMemcpyHostToDevice, streams[i]);

        //convertRGBtoYCbCrKernel<<<gridSize, blockSize, 0, streams[i]>>>(d_inputR, d_inputG, d_inputB, d_outputY, d_outputCb, d_outputCr, size, offset);
        convertRGBtoYCbCrKernel1<<<gridSize, blockSize, 0, streams[i]>>>(d_inputR, d_inputG, d_inputB, d_outputY, d_outputCb, d_outputCr, size, offset);
        cudaMemcpyAsync(&h_outputY[offset], &d_outputY[offset], sizeByte / numStreams, cudaMemcpyDeviceToHost, streams[i]);

        convertRGBtoYCbCrKernel2<<<gridSize, blockSize, 0, streams[i]>>>(d_inputR, d_inputG, d_inputB, d_outputY, d_outputCb, d_outputCr, size, offset);
        cudaMemcpyAsync(&h_outputCb[offset], &d_outputCb[offset], sizeByte / numStreams, cudaMemcpyDeviceToHost, streams[i]);

        convertRGBtoYCbCrKernel3<<<gridSize, blockSize, 0, streams[i]>>>(d_inputR, d_inputG, d_inputB, d_outputY, d_outputCb, d_outputCr, size, offset);
        cudaMemcpyAsync(&h_outputCr[offset], &d_outputCr[offset], sizeByte / numStreams, cudaMemcpyDeviceToHost, streams[i]);
        //cudaMemcpyAsync(&h_outputY[offset], &d_outputY[offset], sizeByte / numStreams, cudaMemcpyDeviceToHost, streams[i]);
        //cudaMemcpyAsync(&h_outputCb[offset], &d_outputCb[offset], sizeByte / numStreams, cudaMemcpyDeviceToHost, streams[i]);
        //cudaMemcpyAsync(&h_outputCr[offset], &d_outputCr[offset], sizeByte / numStreams, cudaMemcpyDeviceToHost, streams[i]);
    }


    // Copy input data from host to device
//    cudaMemcpy(d_inputR, in->rc->data, width * height * sizeof(float), cudaMemcpyHostToDevice);
//    cudaMemcpy(d_inputG, in->gc->data, width * height * sizeof(float), cudaMemcpyHostToDevice);
//    cudaMemcpy(d_inputB, in->bc->data, width * height * sizeof(float), cudaMemcpyHostToDevice);
//    cudaEventRecord(end);
//    cudaEventSynchronize(end);
//    float milliseconds = 0;
//    cudaEventElapsedTime(&milliseconds, start, end);
//    printf("setup time: %f us\n", 1000*milliseconds);
    // Define grid and block dimensions



    // Launch the CUDA kernel




    // Copy the results back from device to host
//    cudaMemcpy(out->rc->data, d_outputY, width * height * sizeof(float), cudaMemcpyDeviceToHost);
//   cudaMemcpy(out->gc->data, d_outputCb, width * height * sizeof(float), cudaMemcpyDeviceToHost);
//    cudaMemcpy(out->bc->data, d_outputCr, width * height * sizeof(float), cudaMemcpyDeviceToHost);
    for (int i = 0; i < numStreams; i++) {
        cudaStreamSynchronize(streams[i]);
        cudaStreamDestroy(streams[i]);
    }

//    gettimeofday (&endtime, NULL);
//    diff = double (endtime.tv_sec) * 1000.0f
//                  + double (endtime.tv_usec) / 1000.0f
//                  - double (starttime.tv_sec) * 1000.0f
//                  - double (starttime.tv_usec) / 1000.0f; // in ms
//    cout<<"val = "<<diff<<endl;
    numChunks = 16;
//    gettimeofday(&starttime, NULL);
    #pragma omp parallel for num_threads(8)
    for(int i = numChunks-1; i >  -1; i--) {
        int offset = i*(size/numChunks);
        memcpy(&out->bc->data[offset], &h_outputCr[offset], sizeByte/numChunks);
    }

    #pragma omp parallel for num_threads(8)
    for(int i = 0; i <  numChunks; i++) {
        int offset = i*(size/numChunks);
        memcpy(&out->rc->data[offset], &h_outputY[offset], sizeByte/numChunks);
//        memcpy(&out->gc->data[offset], &h_outputCb[offset], sizeByte/numChunks);
//        memcpy(&out->bc->data[offset], &h_outputCr[offset], sizeByte/numChunks);
    }
    #pragma omp parallel for num_threads(8)
    for(int i = 0; i <  numChunks; i++) {
        int offset = i*(size/numChunks);
        memcpy(&out->gc->data[offset], &h_outputCb[offset], sizeByte/numChunks);
    }

//    gettimeofday (&endtime, NULL);
//    diff = double (endtime.tv_sec) * 1000.0f
//                  + double (endtime.tv_usec) / 1000.0f
//                  - double (starttime.tv_sec) * 1000.0f
//                  - double (starttime.tv_usec) / 1000.0f; // in ms
//    cout<<"val = "<<diff<<endl;
// Synchronize the stream to ensure all operations are completed

    // Destroy the streams when done

    // Free device memory
    //freeGpu();


//    cudaEventDestroy(start);
//    cudaEventDestroy(end);
    // return out;
}


Channel *
lowPass (Channel *in, Channel *out)
{
  // Applies a simple 3-tap low-pass filter in the X- and Y- dimensions.
  // E.g., blur
  // weights for neighboring pixels
  float a = 0.25;
  float b = 0.5;
  float c = 0.25;

  int width = in->width;
  int height = in->height;

  // out = in; TODO Is this necessary?
  for (int i = 0; i < width * height; i++)
    out->data[i] = in->data[i];

  // In X
  for (int y = 1; y < (width - 1); y++)
    {
      for (int x = 1; x < (height - 1); x++)
        {
          out->data[x * width + y] = a * in->data[(x - 1) * width + y]
                                     + b * in->data[x * width + y]
                                     + c * in->data[(x + 1) * width + y];
        }
    }
  // In Y
  for (int y = 1; y < (width - 1); y++)
    {
      for (int x = 1; x < (height - 1); x++)
        {
          out->data[x * width + y] = a * out->data[x * width + (y - 1)]
                                     + b * out->data[x * width + y]
                                     + c * out->data[x * width + (y + 1)];
        }
    }

  return out;
}

std::vector<mVector> *
motionVectorSearch (Frame *source, Frame *match, int width, int height)
{
  std::vector<mVector> *motion_vectors
      = new std::vector<mVector> (); // empty list of ints

  float Y_weight = 0.5;
  float Cr_weight = 0.25;
  float Cb_weight = 0.25;

  // Window size is how much on each side of the block we search
  int window_size = 16;
  int block_size = 16;

  // How far from the edge we can go since we don't special case the edges
  int inset = (int)max ((float)window_size, (float)block_size);
  int iter = 0;

  for (int my = inset; my < height - (inset + window_size) + 1;
       my += block_size)
    {
      for (int mx = inset; mx < width - (inset + window_size) + 1;
           mx += block_size)
        {

          float best_match_sad = 1e10;
          int best_match_location[2] = { 0, 0 };

          for (int sy = my - window_size; sy < my + window_size; sy++)
            {
              for (int sx = mx - window_size; sx < mx + window_size; sx++)
                {
                  float current_match_sad = 0;
                  // Do the SAD
                  for (int y = 0; y < block_size; y++)
                    {
                      for (int x = 0; x < block_size; x++)
                        {
                          int match_x = mx + x;
                          int match_y = my + y;
                          int search_x = sx + x;
                          int search_y = sy + y;
                          float diff_Y = abs (
                              match->Y->data[match_x * width + match_y]
                              - source->Y->data[search_x * width + search_y]);
                          float diff_Cb = abs (
                              match->Cb->data[match_x * width + match_y]
                              - source->Cb->data[search_x * width + search_y]);
                          float diff_Cr = abs (
                              match->Cr->data[match_x * width + match_y]
                              - source->Cr->data[search_x * width + search_y]);

                          float diff_total = Y_weight * diff_Y
                                             + Cb_weight * diff_Cb
                                             + Cr_weight * diff_Cr;
                          current_match_sad = current_match_sad + diff_total;
                        }
                    } // end SAD

                  if (current_match_sad <= best_match_sad)
                    {
                      best_match_sad = current_match_sad;
                      best_match_location[0] = sx - mx;
                      best_match_location[1] = sy - my;
                    }
                }
            }

          mVector v;
          v.a = best_match_location[0];
          v.b = best_match_location[1];
          motion_vectors->push_back (v);
        }
    }

  return motion_vectors;
}

Frame *
computeDelta (Frame *i_frame_ycbcr, Frame *p_frame_ycbcr,
              std::vector<mVector> *motion_vectors)
{
  Frame *delta = new Frame (p_frame_ycbcr);

  int width = i_frame_ycbcr->width;
  int height = i_frame_ycbcr->height;
  int window_size = 16;
  int block_size = 16;
  // How far from the edge we can go since we don't special case the edges
  int inset = (int)max ((float)window_size, (float)block_size);

  int current_block = 0;
  for (int my = inset; my < width - (inset + window_size) + 1;
       my += block_size)
    {
      for (int mx = inset; mx < height - (inset + window_size) + 1;
           mx += block_size)
        {
          int vector[2];
          vector[0] = (int)motion_vectors->at (current_block).a;
          vector[1] = (int)motion_vectors->at (current_block).b;

          // copy the block
          for (int y = 0; y < block_size; y++)
            {
              for (int x = 0; x < block_size; x++)
                {

                  int src_x = mx + vector[0] + x;
                  int src_y = my + vector[1] + y;
                  int dst_x = mx + x;
                  int dst_y = my + y;
                  delta->Y->data[dst_x * width + dst_y]
                      = delta->Y->data[dst_x * width + dst_y]
                        - i_frame_ycbcr->Y->data[src_x * width + src_y];
                  delta->Cb->data[dst_x * width + dst_y]
                      = delta->Cb->data[dst_x * width + dst_y]
                        - i_frame_ycbcr->Cb->data[src_x * width + src_y];
                  delta->Cr->data[dst_x * width + dst_y]
                      = delta->Cr->data[dst_x * width + dst_y]
                        - i_frame_ycbcr->Cr->data[src_x * width + src_y];
                }
            }

          current_block = current_block + 1;
        }
    }
  return delta;
}

Channel *
downSample (Channel *in)
{
  int width = in->width;
  int height = in->height;
  int w2 = width / 2;
  int h2 = height / 2;

  Channel *out = new Channel ((width / 2), (height / 2));

  for (int y2 = 0, y = 0; y2 < w2; y2++)
    {
      for (int x2 = 0, x = 0; x2 < h2; x2++)
        {

          out->data[x2 * w2 + y2] = in->data[x * width + y];
          x += 2;
        }
      y += 2;
    }

  return out;
}

void
dct8x8 (Channel *in, Channel *out)
{
  int width = in->width;
  int height = in->height;

  // 8x8 block dct on each block
  for (int i = 0; i < width * height; i++)
    {
      in->data[i] -= 128;
      out->data[i] = 0; // zeros
    }

  for (int y = 0; y < width; y += 8)
    {
      for (int x = 0; x < height; x += 8)
        {
          dct8x8_block (&(in->data[x * width + y]),
                        &(out->data[x * width + y]), width);
        }
    }
}

void
round_block (float *in, float *out, int stride)
{
  float quantMatrix[8][8] = {
    { 16, 11, 10, 16, 24, 40, 51, 61 },
    { 12, 12, 14, 19, 26, 58, 60, 55 },
    { 14, 13, 16, 24, 40, 57, 69, 56 },
    { 14, 17, 22, 29, 51, 87, 80, 62 },
    { 18, 22, 37, 56, 68, 109, 103, 77 },
    { 24, 35, 55, 64, 81, 104, 113, 92 },
    { 49, 64, 78, 87, 103, 121, 120, 101 },
    { 72, 92, 95, 98, 112, 100, 103, 99 },
  };

  for (int y = 0; y < 8; y++)
    {
      for (int x = 0; x < 8; x++)
        {
          quantMatrix[x][y] = ceil (quantMatrix[x][y] / QUALITY);
          out[x * stride + y]
              = (float)round (in[x * stride + y] / quantMatrix[x][y]);
        }
    }
}

void
quant8x8 (Channel *in, Channel *out)
{
  int width = in->width;
  int height = in->height;

  for (int i = 0; i < width * height; i++)
    {
      out->data[i] = 0; // zeros
    }

  for (int y = 0; y < width; y += 8)
    {
      for (int x = 0; x < height; x += 8)
        {
          round_block (&(in->data[x * width + y]), &(out->data[x * width + y]),
                       width);
        }
    }
}

void
dcDiff (Channel *in, Channel *out)
{
  int width = in->width;
  int height = in->height;

  int number_of_dc = width * height / 64;
  double *dc_values_transposed = new double[number_of_dc];
  double *dc_values = new double[number_of_dc];

  int iter = 0;
  for (int j = 0; j < width; j += 8)
    {
      for (int i = 0; i < height; i += 8)
        {
          dc_values_transposed[iter] = in->data[i * width + j];
          dc_values[iter] = in->data[i * width + j];
          iter++;
        }
    }

  int new_w = std::max (width / 8, 1);
  int new_h = std::max (height / 8, 1);

  out->data[0] = (float)dc_values[0];

  double prev = 0.;
  iter = 0;
  for (int j = 0; j < new_w; j++)
    {
      for (int i = 0; i < new_h; i++)
        {
          out->data[iter] = (float)(dc_values[i * new_w + j] - prev);
          prev = dc_values[i * new_w + j];
          iter++;
        }
    }
  delete[] dc_values_transposed;
  delete[] dc_values;
}

void
cpyBlock (float *in, float *out, int blocksize, int stride)
{
  for (int j = 0; j < blocksize; j++)
    {
      for (int i = 0; i < blocksize; i++)
        {
          out[i * blocksize + j] = in[i * stride + j];
        }
    }
}

void
zigZagOrder (Channel *in, Channel *ordered)
{
  int width = in->width;
  int height = in->height;
  int zigZagIndex[64]
      = { 0,  1,  8,  16, 9,  2,  3,  10, 17, 24, 32, 25, 18, 11, 4,  5,
          12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6,  7,  14, 21, 28,
          35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
          58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63 };

  int blockNumber = 0;
  float _block[MPEG_CONSTANT];

  for (int x = 0; x < height; x += 8)
    {
      for (int y = 0; y < width; y += 8)
        {
          cpyBlock (&(in->data[x * width + y]), _block, 8,
                    width); // block = in(x:x+7,y:y+7);
          // Put the coefficients in zig-zag order
          float zigZagOrdered[MPEG_CONSTANT] = { 0 };
          for (int index = 0; index < MPEG_CONSTANT; index++)
            {
              zigZagOrdered[index] = _block[zigZagIndex[index]];
            }
          for (int i = 0; i < MPEG_CONSTANT; i++)
            ordered->data[blockNumber * MPEG_CONSTANT + i] = zigZagOrdered[i];
          blockNumber++;
        }
    }
}

void
encode8x8 (Channel *ordered, SMatrix *encoded)
{
  int width = encoded->height;
  int height = encoded->width;
  int num_blocks = height;

  for (int i = 0; i < num_blocks; i++)
    {
      std::string block_encode[MPEG_CONSTANT];
      for (int j = 0; j < MPEG_CONSTANT; j++)
        {
          block_encode[j] = "\0"; // necessary to initialize every string
                                  // position to empty string
        }

      double *block = new double[width];
      for (int y = 0; y < width; y++)
        block[y] = ordered->data[i * width + y];
      int num_coeff = MPEG_CONSTANT; // width
      int encoded_index = 0;
      int in_zero_run = 0;
      int zero_count = 0;

      // Skip DC coefficient
      for (int c = 1; c < num_coeff; c++)
        {
          double coeff = block[c];
          if (coeff == 0)
            {
              if (in_zero_run == 0)
                {
                  zero_count = 0;
                  in_zero_run = 1;
                }
              zero_count = zero_count + 1;
            }
          else
            {
              if (in_zero_run == 1)
                {
                  in_zero_run = 0;
                  block_encode[encoded_index]
                      = "Z" + std::to_string (zero_count);
                  encoded_index = encoded_index + 1;
                }
              block_encode[encoded_index] = std::to_string ((int)coeff);
              encoded_index = encoded_index + 1;
            }
        }

      // If we were in a zero run at the end attach it as well.
      if (in_zero_run == 1)
        {
          if (zero_count > 1)
            {
              block_encode[encoded_index] = "Z" + std::to_string (zero_count);
            }
          else
            {
              block_encode[encoded_index] = "0";
            }
        }

      for (int it = 0; it < MPEG_CONSTANT; it++)
        {
          if (block_encode[it].length () > 0)
            encoded->data[i * width + it] = new std::string (block_encode[it]);
          else
            it = MPEG_CONSTANT;
        }
      delete[] block;
    }
}

int
encode ()
{
  int end_frame = int (N_FRAMES);
  int i_frame_frequency = int (I_FRAME_FREQ);
  struct timeval starttime, endtime;
  double runtime[10] = { 0 };

  // Hardcoded paths
  string image_path
      = "../../inputs/" + string (image_name) + "/" + image_name + ".";
  string stream_path
      = "../../outputs/stream_c_" + string (image_name) + ".xml";

  xmlDocPtr stream = NULL;

  Image *frame_rgb = NULL;
  Image *previous_frame_rgb = NULL;
  Frame *previous_frame_lowpassed = NULL;

  loadImage (0, image_path, &frame_rgb);

  int width = frame_rgb->width;
  int height = frame_rgb->height;
  int npixels = width * height;

  delete frame_rgb;

  createStatsFile ();
  stream = create_xml_stream (width, height, QUALITY, WINDOW_SIZE, BLOCK_SIZE);
  vector<mVector> *motion_vectors = NULL;

    initGPU(width, height); //main loop initGPU
  for (int frame_number = 0; frame_number < end_frame; frame_number++)
    {
      frame_rgb = NULL;
      loadImage (frame_number, image_path, &frame_rgb);

      //  Convert to YCbCr
      print ("Covert to YCbCr...");

      Image *frame_ycbcr = new Image (width, height, FULLSIZE);
      gettimeofday (&starttime, NULL);
      convertRGBtoYCbCr (frame_rgb, frame_ycbcr);
      gettimeofday (&endtime, NULL);
      runtime[0] = double (endtime.tv_sec) * 1000.0f
                   + double (endtime.tv_usec) / 1000.0f
                   - double (starttime.tv_sec) * 1000.0f
                   - double (starttime.tv_usec) / 1000.0f; // in ms

      dump_image (frame_ycbcr, "frame_ycbcr", frame_number);
      delete frame_rgb;

      // We low pass filter Cb and Cr channesl
      print ("Low pass filter...");

      gettimeofday (&starttime, NULL);
      Channel *frame_blur_cb = new Channel (width, height);
      Channel *frame_blur_cr = new Channel (width, height);
      Frame *frame_lowpassed = new Frame (width, height, FULLSIZE);

      lowPass (frame_ycbcr->gc, frame_blur_cb);
      lowPass (frame_ycbcr->bc, frame_blur_cr);

      frame_lowpassed->Y->copy (frame_ycbcr->rc);
      frame_lowpassed->Cb->copy (frame_blur_cb);
      frame_lowpassed->Cr->copy (frame_blur_cr);
      gettimeofday (&endtime, NULL);
      runtime[1] = double (endtime.tv_sec) * 1000.0f
                   + double (endtime.tv_usec) / 1000.0f
                   - double (starttime.tv_sec) * 1000.0f
                   - double (starttime.tv_usec) / 1000.0f; // in ms

      dump_frame (frame_lowpassed, "frame_ycbcr_lowpass", frame_number);
      delete frame_ycbcr;
      delete frame_blur_cb;
      delete frame_blur_cr;

      Frame *frame_lowpassed_final = NULL;

      if (frame_number % i_frame_frequency != 0)
        {
          // We have a P frame
          // Note that in the first iteration we don't enter this branch!

          // Compute the motion vectors
          print ("Motion Vector Search...");

          gettimeofday (&starttime, NULL);
          motion_vectors = motionVectorSearch (
              previous_frame_lowpassed, frame_lowpassed,
              frame_lowpassed->width, frame_lowpassed->height);
          gettimeofday (&endtime, NULL);
          runtime[2] = double (endtime.tv_sec) * 1000.0f
                       + double (endtime.tv_usec) / 1000.0f
                       - double (starttime.tv_sec) * 1000.0f
                       - double (starttime.tv_usec) / 1000.0f; // in ms

          print ("Compute Delta...");
          gettimeofday (&starttime, NULL);
          frame_lowpassed_final = computeDelta (
              previous_frame_lowpassed, frame_lowpassed, motion_vectors);
          gettimeofday (&endtime, NULL);
          runtime[3] = double (endtime.tv_sec) * 1000.0f
                       + double (endtime.tv_usec) / 1000.0f
                       - double (starttime.tv_sec) * 1000.0f
                       - double (starttime.tv_usec) / 1000.0f; // in ms
        }
      else
        {
          // We have a I frame
          motion_vectors = NULL;
          frame_lowpassed_final = new Frame (frame_lowpassed);
        }
      delete frame_lowpassed;
      frame_lowpassed = NULL;

      if (frame_number > 0)
        delete previous_frame_lowpassed;
      previous_frame_lowpassed = new Frame (frame_lowpassed_final);

      // Downsample the difference
      print ("Downsample...");

      gettimeofday (&starttime, NULL);
      Frame *frame_downsampled = new Frame (width, height, DOWNSAMPLE);

      // We don't touch the Y frame
      frame_downsampled->Y->copy (frame_lowpassed_final->Y);
      Channel *frame_downsampled_cb = downSample (frame_lowpassed_final->Cb);
      frame_downsampled->Cb->copy (frame_downsampled_cb);
      Channel *frame_downsampled_cr = downSample (frame_lowpassed_final->Cr);
      frame_downsampled->Cr->copy (frame_downsampled_cr);
      gettimeofday (&endtime, NULL);
      runtime[4] = double (endtime.tv_sec) * 1000.0f
                   + double (endtime.tv_usec) / 1000.0f
                   - double (starttime.tv_sec) * 1000.0f
                   - double (starttime.tv_usec) / 1000.0f; // in ms

      dump_frame (frame_downsampled, "frame_downsampled", frame_number);
      delete frame_lowpassed_final;
      delete frame_downsampled_cb;
      delete frame_downsampled_cr;

      // Convert to frequency domain
      print ("Convert to frequency domain...");

      gettimeofday (&starttime, NULL);
      Frame *frame_dct = new Frame (width, height, DOWNSAMPLE);

      dct8x8 (frame_downsampled->Y, frame_dct->Y);
      dct8x8 (frame_downsampled->Cb, frame_dct->Cb);
      dct8x8 (frame_downsampled->Cr, frame_dct->Cr);
      gettimeofday (&endtime, NULL);
      runtime[5] = double (endtime.tv_sec) * 1000.0f
                   + double (endtime.tv_usec) / 1000.0f
                   - double (starttime.tv_sec) * 1000.0f
                   - double (starttime.tv_usec) / 1000.0f; // in ms

      dump_frame (frame_dct, "frame_dct", frame_number);
      delete frame_downsampled;

      // Quantize the data
      print ("Quantize...");

      gettimeofday (&starttime, NULL);
      Frame *frame_quant = new Frame (width, height, DOWNSAMPLE);

      quant8x8 (frame_dct->Y, frame_quant->Y);
      quant8x8 (frame_dct->Cb, frame_quant->Cb);
      quant8x8 (frame_dct->Cr, frame_quant->Cr);
      gettimeofday (&endtime, NULL);
      runtime[6] = double (endtime.tv_sec) * 1000.0f
                   + double (endtime.tv_usec) / 1000.0f
                   - double (starttime.tv_sec) * 1000.0f
                   - double (starttime.tv_usec) / 1000.0f; // in ms

      dump_frame (frame_quant, "frame_quant", frame_number);
      delete frame_dct;

      // Extract the DC components and compute the differences
      print ("Compute DC differences...");

      gettimeofday (&starttime, NULL);
      Frame *frame_dc_diff = new Frame (1, (width / 8) * (height / 8),
                                        DCDIFF); // dealocate later

      dcDiff (frame_quant->Y, frame_dc_diff->Y);
      dcDiff (frame_quant->Cb, frame_dc_diff->Cb);
      dcDiff (frame_quant->Cr, frame_dc_diff->Cr);
      gettimeofday (&endtime, NULL);
      runtime[7] = double (endtime.tv_sec) * 1000.0f
                   + double (endtime.tv_usec) / 1000.0f
                   - double (starttime.tv_sec) * 1000.0f
                   - double (starttime.tv_usec) / 1000.0f; // in ms

      dump_dc_diff (frame_dc_diff, "frame_dc_diff", frame_number);

      // Zig-zag order for zero-counting
      print ("Zig-zag order...");
      gettimeofday (&starttime, NULL);

      Frame *frame_zigzag
          = new Frame (MPEG_CONSTANT, width * height / MPEG_CONSTANT, ZIGZAG);

      zigZagOrder (frame_quant->Y, frame_zigzag->Y);
      zigZagOrder (frame_quant->Cb, frame_zigzag->Cb);
      zigZagOrder (frame_quant->Cr, frame_zigzag->Cr);
      gettimeofday (&endtime, NULL);
      runtime[8] = double (endtime.tv_sec) * 1000.0f
                   + double (endtime.tv_usec) / 1000.0f
                   - double (starttime.tv_sec) * 1000.0f
                   - double (starttime.tv_usec) / 1000.0f; // in ms

      dump_zigzag (frame_zigzag, "frame_zigzag", frame_number);
      delete frame_quant;

      // Encode coefficients
      print ("Encode coefficients...");

      gettimeofday (&starttime, NULL);
      FrameEncode *frame_encode
          = new FrameEncode (width, height, MPEG_CONSTANT);

      encode8x8 (frame_zigzag->Y, frame_encode->Y);
      encode8x8 (frame_zigzag->Cb, frame_encode->Cb);
      encode8x8 (frame_zigzag->Cr, frame_encode->Cr);
      gettimeofday (&endtime, NULL);
      runtime[9] = double (endtime.tv_sec) * 1000.0f
                   + double (endtime.tv_usec) / 1000.0f
                   - double (starttime.tv_sec) * 1000.0f
                   - double (starttime.tv_usec) / 1000.0f; // in ms

      delete frame_zigzag;

      stream_frame (stream, frame_number, motion_vectors, frame_number - 1,
                    frame_dc_diff, frame_encode);
      write_stream (stream_path, stream);

      delete frame_dc_diff;
      delete frame_encode;

      if (motion_vectors != NULL)
        {
          free (motion_vectors);
          motion_vectors = NULL;
        }

      writestats (frame_number, frame_number % i_frame_frequency, runtime);
    }
    freeGpu();
  closeStats ();
  /* Uncoment to prevent visual studio output window from closing */
  // system("pause");

  return 0;
}

int
main (int args, char **argv)
{
  encode ();
  return 0;
}
