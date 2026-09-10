#pragma once
// live2d-agent: audio playback and mouth ownership for local/private runtime.
#include <windows.h>
#include <mmsystem.h>
#include <fstream>
#include <vector>
#include <string>
#include <cmath>
#include <cstring>
#include <cstdio>
#include <stdexcept>
#include <Model/CubismModel.hpp>
#pragma comment(lib, "winmm.lib")

class AgentAudio {
    HWAVEOUT device = nullptr;
    WAVEHDR header = {};
    WAVEFORMATEX format = {};
    std::vector<char> pcm;
    std::string id;
    bool prepared = false;
    bool managed = false;
    bool ephemeral = false;
    ULONGLONG nextPoll = 0;
    ULONGLONG started = 0;
    unsigned previousPosition = 0;
    unsigned positionUpdates = 0;
    float peakMouth = 0;
    static unsigned u32(const char* p) { unsigned v; std::memcpy(&v,p,4); return v; }
    void status(const char* value) {
        if (id.empty()) return;
        std::ofstream out("speech/" + id + ".status", std::ios::app);
        out << value << " tick_ms=" << GetTickCount64()
            << " position_updates=" << positionUpdates << " peak_mouth=" << peakMouth << "\n";
        out.flush();
    }
    void close() {
        const std::string finishedId = id;
        const bool removeLocalCopy = ephemeral;
        if (device) {
            waveOutReset(device);
            if (prepared) waveOutUnprepareHeader(device,&header,sizeof(header));
            waveOutClose(device);
        }
        device=nullptr; prepared=false; managed=false; ephemeral=false; header={}; pcm.clear();
        if (removeLocalCopy && !finishedId.empty()) {
            DeleteFileA(("speech/" + finishedId + ".wav").c_str());
            DeleteFileA(("speech/" + finishedId + ".claimed").c_str());
            DeleteFileA(("speech/" + finishedId + ".ephemeral").c_str());
        }
        id.clear();
    }
    void load() {
        std::ifstream in("speech/" + id + ".wav",std::ios::binary|std::ios::ate);
        if (!in) throw std::runtime_error("wave_missing");
        auto size=in.tellg();
        if (size<44 || size>32*1024*1024) throw std::runtime_error("wave_size");
        std::vector<char> bytes(static_cast<size_t>(size));
        in.seekg(0); in.read(bytes.data(),bytes.size());
        if (!in || std::memcmp(bytes.data(),"RIFF",4) || std::memcmp(bytes.data()+8,"WAVE",4)) throw std::runtime_error("wave_header");
        const size_t end=static_cast<size_t>(u32(bytes.data()+4))+8;
        if (end!=bytes.size()) throw std::runtime_error("riff_size");
        bool gotFormat=false,gotData=false;
        for (size_t offset=12;offset+8<=end;) {
            const char* chunk=bytes.data()+offset;
            const size_t n=u32(chunk+4);
            if (n>end-offset-8) throw std::runtime_error("wave_chunk");
            if (!std::memcmp(chunk,"fmt ",4)) {
                if (gotFormat || n<16) throw std::runtime_error("wave_format");
                format={}; std::memcpy(&format,chunk+8,16); gotFormat=true;
            } else if (!std::memcmp(chunk,"data",4)) {
                if (gotData) throw std::runtime_error("duplicate_data");
                pcm.assign(chunk+8,chunk+8+n); gotData=true;
            }
            offset+=8+n+(n&1);
            if (offset>end) throw std::runtime_error("wave_padding");
        }
        if (!gotFormat || !gotData || pcm.empty() || format.wFormatTag!=WAVE_FORMAT_PCM ||
            format.wBitsPerSample!=16 || (format.nChannels!=1 && format.nChannels!=2) ||
            format.nSamplesPerSec<8000 || format.nSamplesPerSec>192000 ||
            format.nBlockAlign!=format.nChannels*2 ||
            format.nAvgBytesPerSec!=format.nSamplesPerSec*format.nBlockAlign ||
            pcm.size()%format.nBlockAlign) throw std::runtime_error("unsupported_pcm");
        if (waveOutOpen(&device,WAVE_MAPPER,&format,0,0,CALLBACK_NULL)!=MMSYSERR_NOERROR) throw std::runtime_error("device_open_failed");
        header={}; header.lpData=pcm.data(); header.dwBufferLength=static_cast<DWORD>(pcm.size());
        if (waveOutPrepareHeader(device,&header,sizeof(header))!=MMSYSERR_NOERROR) throw std::runtime_error("prepare_failed");
        prepared=true;
        started=GetTickCount64();
        if (waveOutWrite(device,&header,sizeof(header))!=MMSYSERR_NOERROR) throw std::runtime_error("write_failed");
        status("playback_submitted");
    }
public:
    AgentAudio() = default;
    AgentAudio(const AgentAudio&)=delete;
    AgentAudio& operator=(const AgentAudio&)=delete;
    ~AgentAudio() { if(device) status("interrupted"); close(); }

    bool IsBusy() const {
        return device != nullptr || managed || GetFileAttributesA("speech.ready") != INVALID_FILE_ATTRIBUTES;
    }

    bool QueueLocalWave(const std::string& sourcePath) {
        if (IsBusy() || GetFileAttributesA(sourcePath.c_str()) == INVALID_FILE_ATTRIBUTES) return false;
        CreateDirectoryA("speech", nullptr);
        static volatile LONG serial = 0;
        const unsigned long sequence = static_cast<unsigned long>(InterlockedIncrement(&serial));
        char candidate[33] = {};
        sprintf_s(candidate, sizeof(candidate), "%016llx%08lx%08lx",
            static_cast<unsigned long long>(GetTickCount64()),
            static_cast<unsigned long>(GetCurrentProcessId()), sequence);
        const std::string queuedId(candidate);
        const std::string destination = "speech/" + queuedId + ".wav";
        const std::string marker = "speech/" + queuedId + ".ephemeral";
        const std::string tempReady = "speech.ready." + queuedId + ".tmp";
        if (!CopyFileA(sourcePath.c_str(), destination.c_str(), TRUE)) return false;
        {
            std::ofstream markerOut(marker, std::ios::binary | std::ios::trunc);
            if (!markerOut) { DeleteFileA(destination.c_str()); return false; }
            markerOut << "1";
        }
        {
            std::ofstream readyOut(tempReady, std::ios::binary | std::ios::trunc);
            if (!readyOut) {
                DeleteFileA(destination.c_str()); DeleteFileA(marker.c_str()); return false;
            }
            readyOut << queuedId;
        }
        if (!MoveFileExA(tempReady.c_str(), "speech.ready", MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
            DeleteFileA(tempReady.c_str()); DeleteFileA(destination.c_str()); DeleteFileA(marker.c_str()); return false;
        }
        return true;
    }

    void update(Live2D::Cubism::Framework::CubismModel* model,
        const Live2D::Cubism::Framework::csmVector<Live2D::Cubism::Framework::CubismIdHandle>& ids) {
        if (!device && GetTickCount64()>=nextPoll) {
            nextPoll=GetTickCount64()+100;
            HANDLE dispatchGate=CreateFileA("speech.lock",GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
            if(dispatchGate!=INVALID_HANDLE_VALUE) {
            std::ifstream ready("speech.ready");
            std::string candidate; ready>>candidate; ready.close();
            if (!candidate.empty()) {
                if (candidate.size()!=32 || candidate.find_first_not_of("0123456789abcdef")!=std::string::npos) {
                    DeleteFileA("speech.ready");
                } else {
                    id=candidate;
                    const std::string claim="speech/"+id+".claimed";
                    HANDLE f=CreateFileA(claim.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
                    if (f!=INVALID_HANDLE_VALUE) {
                        CloseHandle(f); managed=true;
                        ephemeral = GetFileAttributesA(("speech/" + id + ".ephemeral").c_str()) != INVALID_FILE_ATTRIBUTES;
                        previousPosition=positionUpdates=0; peakMouth=0;
                        status("accepted");
                        try {
                            if (ids.GetSize()==0) throw std::runtime_error("lip_group_missing");
                            for (int i=0;i<ids.GetSize();++i) {
                                bool found=false;
                                for (int p=0;p<model->GetParameterCount();++p) if(model->GetParameterId(p)==ids[i]) found=true;
                                if(!found) throw std::runtime_error("lip_parameter_missing");
                            }
                            load();
                        } catch (const std::exception& error) { status(error.what()); close(); }
                    } else if (GetLastError()==ERROR_FILE_EXISTS) { status("duplicate_suppressed"); id.clear(); }
                    else { status("claim_failed"); id.clear(); }
                    DeleteFileA("speech.ready");
                }
            }
            CloseHandle(dispatchGate);
            }
        }
        float mouth=0;
        if (device) {
            try {
                MMTIME position={}; position.wType=TIME_SAMPLES;
                if(waveOutGetPosition(device,&position,sizeof(position))!=MMSYSERR_NOERROR) throw std::runtime_error("position_failed");
                unsigned frame=0;
                if(position.wType==TIME_SAMPLES) frame=position.u.sample;
                else if(position.wType==TIME_BYTES) frame=position.u.cb/format.nBlockAlign;
                else if(position.wType==TIME_MS) frame=static_cast<unsigned>(static_cast<unsigned long long>(position.u.ms)*format.nSamplesPerSec/1000);
                else throw std::runtime_error("position_type_unsupported");
                if(frame<previousPosition) throw std::runtime_error("position_regressed");
                if(frame>previousPosition) { if(positionUpdates++==0) status("device_position_advanced"); previousPosition=frame; }
                if(header.dwFlags&WHDR_DONE) { status("playback_completed"); close(); }
                else {
                    if(GetTickCount64()-started>10000+1000ULL*pcm.size()/format.nAvgBytesPerSec) throw std::runtime_error("playback_timeout");
                    const size_t begin=static_cast<size_t>(frame)*format.nBlockAlign;
                    const size_t finish=(std::min)(pcm.size(),begin+static_cast<size_t>(format.nSamplesPerSec/100)*format.nBlockAlign);
                    double sum=0; size_t count=0;
                    for(size_t p=begin;p+2<=finish;p+=2) { short sample; std::memcpy(&sample,pcm.data()+p,2); const double v=sample/32768.0; sum+=v*v; ++count; }
                    if(count) mouth=static_cast<float>((std::min)(1.0,std::sqrt(sum/count)*4.0));
                    peakMouth=(std::max)(peakMouth,mouth);
                }
            } catch(const std::exception& error) { status(error.what()); close(); }
        }
        // Own configured mouth parameters only while playback remains active.
        if(managed) for(int i=0;i<ids.GetSize();++i) {
            for(int p=0;p<model->GetParameterCount();++p) if(model->GetParameterId(p)==ids[i]) {
                model->SetParameterValue(p,mouth); break;
            }
        }
    }
};
