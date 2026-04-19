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

GuessDecompressor::~GuessDecompressor()
{
  delete backend_;
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

bool GuessDecompressor::Guess(InputAbstract* input, cvmfs::Sink* output)
{
  assert(!backend_);
  assert(expected_fmt_ != ExpectedContentFormat::kInvalid);
  if (input->chunk_size() == 0 && input->has_chunk_left()) {
    input->NextChunk();
  }
  const unsigned char * const data = input->chunk();
  const size_t data_len = input->chunk_size();

  /* These are some reliable longer signatures of compression methods
   * implemented in CVMFS, for potential future use:
  const unsigned char zlib_sig[2] = {0x78, 0x9c};
  const unsigned char zstd_sig[4] = {0x28, 0xb5, 0x2f, 0xfd};
  */

  const char expected_first_byte = ExpectedFirstByte(expected_fmt_);
  const char first_byte = data[0];
  switch (first_byte) {
    case 0x78: {
      alg_ = zip::Algorithm::kZlib;
      backend_ = new zip::ZlibDecompressor(alg_);
      break;
    }
    case 0x28: {
      alg_ = zip::Algorithm::kZstd;
      backend_ = new zip::ZstdDecompressor(alg_);
      break;
    }
    case 'C':
    case '-':
    case '{':
    case 'S':
    {
      if (first_byte == expected_first_byte) {
        alg_ = zip::Algorithm::kNoCompression;
        backend_ = new zip::EchoDecompressor(alg_);
        break;
      } else {
        LogCvmfs(kLogCvmfs, kLogStderr, "Decompression autoconfiguration failed: expected format %d with first byte 0x%hhx, got 0x%hhx", expected_fmt_, expected_first_byte, first_byte);
        assert(false);
        return false;
      }
    }
    default: {
      LogCvmfs(kLogCvmfs, kLogStderr, "Decompression autoconfiguration failed: expected format %d with first byte 0x%hhx, got 0x%hhx (doesn't match any expected compression or content format)", expected_fmt_, expected_first_byte, first_byte);
      assert(false);
      return false;
    }
  }
  return true;
}

StreamStates GuessDecompressor::DecompressStream(InputAbstract* input,
                                                 cvmfs::Sink* output) {
  if (!backend_) {
    bool ok = Guess(input, output);
    if (!ok) {
      return kStreamDataError;
    }
  }

  const zip::StreamStates ret = backend_->DecompressStream(input, output);
  return ret;
}

std::string GuessDecompressor::Describe() {
  return "GuessDecompressor";
}

}  // namespace zip
