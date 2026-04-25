/**
 * This file is part of the CernVM File System.
 *
 * This is a wrapper around zlib.  It provides
 * a set of functions to conveniently compress and decompress stuff.
 * Almost all of the functions return true on success, otherwise false.
 *
 * TODO: think about code deduplication
 */

#include "compressor.h"

#include <alloca.h>
#include <stdlib.h>
#include <sys/stat.h>

#include <algorithm>
#include <cassert>
#include <cstring>
#include <iostream>

#include "cvmfs_config.h"
#include "compressor_echo.h"
#include "compressor_zlib.h"
#include "compressor_zstd.h"

#include "crypto/hash.h"
#include "util/exception.h"
#include "util/logging.h"
#include "util/platform.h"
#include "util/posix.h"
#include "util/smalloc.h"

namespace zip {

void Compressor::RegisterPlugins() {
  RegisterPlugin<ZlibCompressor>();
  RegisterPlugin<ZstdCompressor>();
  RegisterPlugin<EchoCompressor>();
}

StreamStates Compressor::CompressStream(InputAbstract* input,
                                        cvmfs::MemSink* output,
                                        const bool flush) {
  if (!is_healthy_) {
    return kStreamError;
  }

  do {
    if (input->GetIdxInsideChunk() < input->chunk_size()
        && input->chunk_size() != 0) {
      // still stuff to process in the current chunk
    } else if (!input->NextChunk() && output->size() < output->pos()) {
      return kStreamIOError;
    }
    StreamStates step_ret = StreamingStep(input, output, flush);
    if (step_ret != kStreamContinue) {
      return step_ret;
    }

    if (output->size() == output->pos()) {
      return kStreamOutBufFull;
    }
  } while (input->has_chunk_left()
          || (input->GetIdxInsideChunk() < input->chunk_size()
              && input->chunk_size() != 0));
  return kStreamEnd;
}

}  // namespace zlib
