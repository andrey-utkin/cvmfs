/**
 * This file is part of the CernVM File System.
 */

#include <cstring>

#include "decompressor_guess.h"

namespace zip {

GuessDecompressor::GuessDecompressor(const zip::Algorithms& alg)
    : Decompressor(alg)
    , backend_(NULL)
    , expected_fmt_(ExpectedContentFormat::kInvalid)
{
}

GuessDecompressor::GuessDecompressor(enum ExpectedContentFormat fmt)
    : Decompressor(zip::Algorithm::kGuessDecompression)
    , backend_(NULL)
    , expected_fmt_(fmt)
{
}

void GuessDecompressor::SetExpectedFormat(enum ExpectedContentFormat fmt)
{
  expected_fmt_ = fmt;
}

char GuessDecompressor::ExpectedFirstByte(enum ExpectedContentFormat fmt)
{
  assert(fmt != kInvalid);
#pragma GCC diagnostic push
#pragma GCC diagnostic error "-Wswitch"
  switch (fmt) {
    case kManifest: return 'C';
    case kPEM:      return '-';
    case kJSON:     return '{';
    case kSQLite3:  return 'S';
    case kInvalid:  return '\0';
  }
#pragma GCC diagnostic pop
}

bool GuessDecompressor::WillHandle(const zip::Algorithms &alg) {
  return alg == zip::Algorithm::kGuessDecompression;
}


Decompressor* GuessDecompressor::Clone() {
  return new GuessDecompressor(zip::Algorithm::kGuessDecompression);
}

void GuessDecompressor::Guess(InputAbstract* input, cvmfs::Sink* output)
{
  assert(!backend_);
  assert(expected_fmt_ != ExpectedContentFormat::kInvalid);
  if (input->chunk_size() == 0 && input->has_chunk_left()) {
    input->NextChunk();
  }
  const unsigned char * const data = input->chunk();
  const size_t data_len = input->chunk_size();

  // What CVMFS tends to create. See with:
  // for x in /srv/cvmfs/*/data/*/*; do file $x; xxd $x | head -n1; done
  const unsigned char zlib_sig[2] = {0x78, 0x9c};
  const unsigned char zstd_sig[4] = {0x28, 0xb5, 0x2f, 0xfd};

  // TODO test that decompression is successful.
  // What if it's just such a file, in a repo having compression disabled?
  // But that's not the default configuration so less important.
#if 0
  if (data_len >= sizeof(zlib_sig) && !memcmp(data, zlib_sig, sizeof(zlib_sig))) {
    alg_ = zip::Algorithm::kZlib;
  } else if (data_len >= sizeof(zstd_sig) && !memcmp(data, zstd_sig, sizeof(zstd_sig))) {
    alg_ = zip::Algorithm::kZstd;
  } else {
    alg_ = zip::Algorithm::kNoCompression;
  }
#endif
  const char clear = ExpectedFirstByte(expected_fmt_);
  switch (data[0]) {
    case 0x78: alg = zip::Algorithm::kZlib; break;
    case 0x28: alg = zip::Algorithm::kZstd; break;
    case clear: alg = zip::Algorithm::kNoCompression; break;
    default: assert(false); alg = zip::Algorithm::kNoCompression;
  }
  backend_ = zip::Decompressor::Construct(alg_);
}

StreamStates GuessDecompressor::DecompressStream(InputAbstract* input,
                                                 cvmfs::Sink* output) {
  if (!backend_) {
    Guess(input, output);
  }

  const zip::StreamStates ret = backend_->DecompressStream(input, output);
  return ret;
}

std::string GuessDecompressor::Describe() {
  return "GuessDecompressor";
}

}  // namespace zip
