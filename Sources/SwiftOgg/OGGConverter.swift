import Foundation
import AVFAudio
import AVFoundation

public enum OGGConverterError: Error {
    case failedToCreateAVAudioChannelLayout
    case failedToCreatePCMBuffer
    case other(Error)
}

public class OGGConverter {
    public static func convertOpusOGGToM4aFile(src: URL, dest: URL) throws {
        do {
            let data = try Data(contentsOf: src)
            let decoder = try OGGDecoder(audioData: data)
            let layoutTag = decoder.numChannels == 1
                ? kAudioChannelLayoutTag_Mono
                : kAudioChannelLayoutTag_Stereo
            guard let layout = AVAudioChannelLayout(layoutTag: layoutTag) else { throw OGGConverterError.failedToCreateAVAudioChannelLayout }
            
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(decoder.sampleRate), interleaved: true, channelLayout: layout)
            guard let buffer = decoder.pcmData.toPCMBuffer(format: format) else { throw OGGConverterError.failedToCreatePCMBuffer }
            var settings: [String : Any] = [:]

            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVSampleRateKey] = buffer.format.sampleRate
            settings[AVNumberOfChannelsKey] = buffer.format.channelCount
            settings[AVLinearPCMIsFloatKey] = (buffer.format.commonFormat == .pcmFormatFloat32)

            let destFile = try AVAudioFile(forWriting: dest, settings: settings, commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            try destFile.write(from: buffer)
        } catch let error as OGGConverterError  {
            throw error
        } catch {
            // wrap lower level errors
            throw OGGConverterError.other(error)
        }
    }
    
    public static func convertM4aFileToOpusOGG(src: URL, dest: URL) throws {
        do {
            let srcFile = try AVAudioFile(
                forReading: src,
                commonFormat: .pcmFormatInt16,
                interleaved: false
            )
            let format = srcFile.processingFormat
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(srcFile.length)
            ) else { throw OGGConverterError.failedToCreatePCMBuffer }
            try srcFile.read(into: buffer)
            let opus = try convert(outputFormat: format, inputBuffer: buffer)
            try opus.write(to: dest)
        } catch let error as OGGConverterError  {
            throw error
        } catch {
            // wrap lower level errors
            throw OGGConverterError.other(error)
        }
    }
    
    public static func convert(data: Data) throws -> AVAudioPCMBuffer {
        let decoder = try OGGDecoder(audioData: data)
        let layoutTag = decoder.numChannels == 1
            ? kAudioChannelLayoutTag_Mono
            : kAudioChannelLayoutTag_Stereo

        guard
            let layout = AVAudioChannelLayout(layoutTag: layoutTag)
        else {
            throw OGGConverterError.failedToCreateAVAudioChannelLayout
        }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(decoder.sampleRate),
            interleaved: true,
            channelLayout: layout
        )

        guard
            let buffer = decoder.pcmData.toPCMBuffer(format: format)
        else {
            throw OGGConverterError.failedToCreatePCMBuffer
        }
        
        return buffer
    }
    
    public static func convert(outputFormat: AVAudioFormat, inputBuffer: AVAudioPCMBuffer) throws -> Data {
        let streamDescription = inputBuffer.format.streamDescription.pointee
        let encoder = try OGGEncoder(format: streamDescription, opusRate: Int32(outputFormat.sampleRate), application: .voip)
        let data = inputBuffer.int16ChannelData()
        try encoder.encode(pcm: data)
        let opus = encoder.bitstream(flush: true)
        return opus
    }
}

extension Data {
  func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let streamDesc = format.streamDescription.pointee
    let frameCapacity = UInt32(count) / streamDesc.mBytesPerFrame
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }

    buffer.frameLength = buffer.frameCapacity
    let audioBuffer = buffer.audioBufferList.pointee.mBuffers
    guard let mData = audioBuffer.mData else { return nil }
      withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
        if let addr = rawBufferPointer.baseAddress {
            mData.copyMemory(from: addr, byteCount: Int(audioBuffer.mDataByteSize))
        }
    }
    return buffer
  }
}

extension AVAudioPCMBuffer {
    func int16ChannelData() -> Data {
        let channelCount = 1
        let channels = UnsafeBufferPointer(start: int16ChannelData, count: channelCount)
        let ch0Data = NSData(
            bytes: channels[0],
            length: Int(frameCapacity * format.streamDescription.pointee.mBytesPerFrame)
        )
        return ch0Data as Data
    }
}

