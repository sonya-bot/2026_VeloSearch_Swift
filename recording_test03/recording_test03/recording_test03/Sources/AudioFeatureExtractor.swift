import Foundation
import AVFoundation
import Accelerate
import CoreML

class AudioFeatureExtractor {
    private let sampleRate: Double = 44100.0
    private let nFft: Int = 1024
    private let hopLength: Int = 512
    private let nMels: Int = 64
    private let targetFrames: Int = 349
    private let requiredSamples: Int = 179200
    
    private var bufferL: [Float] = []
    private var bufferR: [Float] = []
    
    var currentBufferCount: Int {
        return bufferL.count
    }
    
    // Melフィルター行列 [Melビン(64)][周波数ビン(513)]
    private var melWeights: [[Float]] = []
    
    // FFT用のセットアップ
    private var fftSetup: vDSP_DFT_Setup?
    private var window: [Float]
    
    init() {
        // 1. Hann窓の初期化
        window = [Float](repeating: 0.0, count: nFft)
        vDSP_hann_window(&window, vDSP_Length(nFft), Int32(vDSP_HANN_NORM))
        
        // 2. FFTのセットアップ (vDSP_DFT)
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(nFft), vDSP_DFT_Direction.FORWARD)
        
        // 3. Pythonから書き出したMelフィルター行列の読み込み
        loadMelFilters()
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
    
    private func loadMelFilters() {
        guard let path = Bundle.main.path(forResource: "mel_filters", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let weightsDouble = json["weights"] as? [Double] else {
            print("エラー: mel_filters.json が見つからないか破損しています。")
            return
        }
        let weightsFlat = weightsDouble.map { Float($0) }
        
        let nStft = nFft / 2 + 1 // 513
        melWeights = Array(repeating: Array(repeating: 0.0, count: nStft), count: nMels)
        
        // Pythonの [n_stft, n_mels] (513 x 64) をSwiftの扱いやすい [64][513] に転置して格納
        for f in 0..<nStft {
            for m in 0..<nMels {
                melWeights[m][f] = weightsFlat[f * nMels + m]
            }
        }
        print("Melフィルター (64 x 513) のロード完了")
    }
    
    func appendAndExtract(buffer: AVAudioPCMBuffer) -> MLMultiArray? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        
        let ptrL = channelData[0]
        let ptrR = buffer.format.channelCount > 1 ? channelData[1] : channelData[0]
        
        bufferL.append(contentsOf: UnsafeBufferPointer(start: ptrL, count: frameLength))
        bufferR.append(contentsOf: UnsafeBufferPointer(start: ptrR, count: frameLength))
        
        if bufferL.count >= requiredSamples {
            let processL = Array(bufferL.prefix(requiredSamples))
            let processR = Array(bufferR.prefix(requiredSamples))
            
            // バッファをクリア（※オーバーラップさせたい場合は suffix 等を残す）
            bufferL.removeAll(keepingCapacity: true)
            bufferR.removeAll(keepingCapacity: true)
            
            return processFeatures(pcmL: processL, pcmR: processR)
        }
        return nil
    }
    
    private func processFeatures(pcmL: [Float], pcmR: [Float]) -> MLMultiArray? {
        guard let setup = fftSetup else { return nil }
        let nStft = nFft / 2 + 1 // 513
        
        // 結果格納用の配列 [CH][Mel][Frame]
        var logMelL = Array(repeating: Array(repeating: Float(0), count: targetFrames), count: nMels)
        var logMelR = Array(repeating: Array(repeating: Float(0), count: targetFrames), count: nMels)
        var cosIpd  = Array(repeating: Array(repeating: Float(0), count: targetFrames), count: nMels)
        var sinIpd  = Array(repeating: Array(repeating: Float(0), count: targetFrames), count: nMels)
        var ild     = Array(repeating: Array(repeating: Float(0), count: targetFrames), count: nMels)
        
        // テンポラリ配列
        var realL = [Float](repeating: 0, count: nFft)
        var imagL = [Float](repeating: 0, count: nFft)
        var realR = [Float](repeating: 0, count: nFft)
        var imagR = [Float](repeating: 0, count: nFft)
        
        // 1. フレーム単位での STFT 実行
        for t in 0..<targetFrames {
            let start = t * hopLength
            let end = start + nFft
            // 安全装置（配列外アクセス防止）
            guard end <= pcmL.count else { break }
            
            var windowedL = [Float](repeating: 0, count: nFft)
            var windowedR = [Float](repeating: 0, count: nFft)
            
            // 窓関数適用
            vDSP_vmul(Array(pcmL[start..<end]), 1, window, 1, &windowedL, 1, vDSP_Length(nFft))
            vDSP_vmul(Array(pcmR[start..<end]), 1, window, 1, &windowedR, 1, vDSP_Length(nFft))
            
            // FFT実行
            var inputImag = [Float](repeating: 0, count: nFft)
            vDSP_DFT_Execute(setup, &windowedL, &inputImag, &realL, &imagL)
            vDSP_DFT_Execute(setup, &windowedR, &inputImag, &realR, &imagR)
            
            var powerL = [Float](repeating: 0, count: nStft)
            var powerR = [Float](repeating: 0, count: nStft)
            var crossReal = [Float](repeating: 0, count: nStft)
            var crossImag = [Float](repeating: 0, count: nStft)
            
            // スペクトルの計算
            for f in 0..<nStft {
                let rl = realL[f], il = imagL[f]
                let rr = realR[f], ir = imagR[f]
                
                // パワースペクトル (Re^2 + Im^2)
                powerL[f] = rl*rl + il*il
                powerR[f] = rr*rr + ir*ir
                
                // クロススペクトル L * conj(R) -> (rl+i*il)*(rr-i*ir) = (rl*rr + il*ir) + i*(il*rr - rl*ir)
                crossReal[f] = rl*rr + il*ir
                crossImag[f] = il*rr - rl*ir
            }
            
            // 2. Melフィルターバンクの適用とLog変換
            for m in 0..<nMels {
                var melPwrL: Float = 0
                var melPwrR: Float = 0
                var melCrossR: Float = 0
                var melCrossI: Float = 0
                
                for f in 0..<nStft {
                    let w = melWeights[m][f]
                    if w > 0 {
                        melPwrL += powerL[f] * w
                        melPwrR += powerR[f] * w
                        melCrossR += crossReal[f] * w
                        melCrossI += crossImag[f] * w
                    }
                }
                
                // AmplitudeToDB (10 * log10(power))
                let l_db = 10.0 * log10(max(melPwrL, 1e-10))
                let r_db = 10.0 * log10(max(melPwrR, 1e-10))
                logMelL[m][t] = l_db
                logMelR[m][t] = r_db
                ild[m][t] = l_db - r_db
                
                // IPDの計算 (Angle = atan2(Im, Re))
                let angle = atan2(melCrossI, melCrossR)
                cosIpd[m][t] = cos(angle)
                sinIpd[m][t] = sin(angle)
            }
        }
                
        // 3. Pythonに合わせたマスキングと正規化 (Threshold = max - 25.0dB)
        var sumL: Float = 0
        var sqSumL: Float = 0
        var sumR: Float = 0
        var sqSumR: Float = 0
        let totalElements = Float(nMels * targetFrames)
        
        var maxEnergy: Float = -1000.0
        var frameEnergies = [Float](repeating: 0, count: targetFrames)
        
        for t in 0..<targetFrames {
            var eSum: Float = 0
            for m in 0..<nMels {
                let vL = logMelL[m][t]
                let vR = logMelR[m][t]
                sumL += vL; sqSumL += vL*vL
                sumR += vR; sqSumR += vR*vR
                eSum += vL
            }
            let avgEnergy = eSum / Float(nMels)
            frameEnergies[t] = avgEnergy
            if avgEnergy > maxEnergy { maxEnergy = avgEnergy }
        }
        
        // 統合平均と標準偏差
        let meanAll = (sumL + sumR) / (totalElements * 2)
        let variance = ((sqSumL + sqSumR) / (totalElements * 2)) - (meanAll * meanAll)
        let stdAll = sqrt(max(variance, 0)) + 1e-6
        
        let threshold = maxEnergy - 25.0
        
        // 4. 最終テンソルへの書き込み
        do {
            // [1, 5, 64, 349] の MLMultiArray 作成 (Float16)
            let multiArray = try MLMultiArray(shape: [1, 5, 64, 349] as [NSNumber], dataType: .float16)
            
            for m in 0..<nMels {
                for t in 0..<targetFrames {
                    let isSilence = frameEnergies[t] < threshold
                    
                    // 正規化
                    let normL = stdAll < 1e-4 ? 0 : (logMelL[m][t] - meanAll) / stdAll
                    let normR = stdAll < 1e-4 ? 0 : (logMelR[m][t] - meanAll) / stdAll
                    
                    // マスキング適用
                    let outCos = isSilence ? 0.0 : cosIpd[m][t]
                    let outSin = isSilence ? 0.0 : sinIpd[m][t]
                    let outIld = isSilence ? 0.0 : ild[m][t]
                    
                    // MLMultiArray への代入 [1(0), CH, Mel, Frame]
                    multiArray[[0, 0, m, t] as [NSNumber]] = NSNumber(value: normL)
                    multiArray[[0, 1, m, t] as [NSNumber]] = NSNumber(value: normR)
                    multiArray[[0, 2, m, t] as [NSNumber]] = NSNumber(value: outCos)
                    multiArray[[0, 3, m, t] as [NSNumber]] = NSNumber(value: outSin)
                    multiArray[[0, 4, m, t] as [NSNumber]] = NSNumber(value: outIld)
                }
            }
            return multiArray
        } catch {
            print("MLMultiArray展開エラー: \(error)")
            return nil
        }
    }
}