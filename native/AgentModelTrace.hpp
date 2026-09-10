#pragma once
// Opt-in, bounded model diagnostics. Never changes model parameters.
#include <windows.h>
#include <fstream>
#include <vector>
#include <string>
#include <algorithm>
#include <Model/CubismModel.hpp>
#include <Id/CubismId.hpp>
#include <Motion/CubismMotionJson.hpp>
#include <Utils/CubismJson.hpp>
class AgentModelTrace {
    bool enabled=false, initialized=false;
    ULONGLONG start=0;
    struct Range { float lo,hi; };
    std::vector<Range> ranges[3];
    std::vector<std::string> names;
    unsigned frames[3]={}, vertexFrames=0, motionStarts=0, motionFailures=0;
public:
    AgentModelTrace(){enabled=GetFileAttributesA("motion-trace.enable")!=INVALID_FILE_ATTRIBUTES;}
    void input(const unsigned char* buffer, int size, const char* name){
        if(!enabled)return;
        std::ofstream out("motion-input.tsv",std::ios::app);
        out<<name<<"\tbytes="<<size<<"\tbuffer="<<(buffer!=nullptr);
        if(buffer){
            Live2D::Cubism::Framework::CubismMotionJson json(buffer,size);
            out<<"\tvalid="<<json.IsValid();
            if(json.IsValid())out<<"\tconsistent="<<json.HasConsistency();
        }
        out<<"\n";
    }
    void motion(bool ok){if(enabled){++motionStarts;if(!ok)++motionFailures;}}
    void observe(Live2D::Cubism::Framework::CubismModel* model,int stage){
        if(!enabled)return;
        if(!initialized){
            initialized=true;start=GetTickCount64();
            std::ofstream meta("model-inventory.tsv");
            meta<<"kind\tid\tminimum\tmaximum\tdefault\n";
            for(int p=0;p<model->GetParameterCount();++p){
                names.push_back(model->GetParameterId(p)->GetString().GetRawString());
                meta<<"parameter\t"<<names.back()<<"\t"<<model->GetParameterMinimumValue(p)<<"\t"<<model->GetParameterMaximumValue(p)<<"\t"<<model->GetParameterDefaultValue(p)<<"\n";
                for(int s=0;s<3;++s)ranges[s].push_back({1e30f,-1e30f});
            }
            for(int p=0;p<model->GetPartCount();++p)
                meta<<"part\t"<<model->GetPartId(p)->GetString().GetRawString()<<"\t"<<model->GetPartOpacity(p)<<"\t0\t0\n";
        }
        if(GetTickCount64()-start>20000)return;
        ++frames[stage];
        for(int p=0;p<model->GetParameterCount();++p){
            float v=model->GetParameterValue(p);
            ranges[stage][p].lo=(std::min)(ranges[stage][p].lo,v);
            ranges[stage][p].hi=(std::max)(ranges[stage][p].hi,v);
        }
        if(stage==2){
            bool changed=false;
            for(int d=0;d<model->GetDrawableCount();++d)changed|=model->GetDrawableDynamicFlagVertexPositionsDidChange(d);
            if(changed)++vertexFrames;
        }
    }
    ~AgentModelTrace(){
        if(!enabled||!initialized)return;
        std::ofstream out("model-trace.tsv");
        out<<"stage\tid\tminimum\tmaximum\trange\n";
        for(int s=0;s<3;++s)for(size_t p=0;p<names.size();++p)
            out<<s<<"\t"<<names[p]<<"\t"<<ranges[s][p].lo<<"\t"<<ranges[s][p].hi<<"\t"<<ranges[s][p].hi-ranges[s][p].lo<<"\n";
        std::ofstream stats("model-trace-summary.txt");
        stats<<"motion_starts="<<motionStarts<<"\nmotion_failures="<<motionFailures<<"\nframes="<<frames[2]<<"\nvertex_changed_frames="<<vertexFrames<<"\n";
    }
};
