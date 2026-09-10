#pragma once
#include <windows.h>
#include <fstream>
#include <string>
#include <vector>
#include <cmath>
#include <sstream>
#include <Model/CubismModel.hpp>
#include <Motion/CubismExpressionMotion.hpp>
#include <Id/CubismId.hpp>
// Local numbered audition commands; no model IDs or executable commands.
class AgentExpression {
    std::string id;
    ULONGLONG nextPoll=0, startedAt=0;
    bool tracking=false;
    std::vector<int> indices;
    std::vector<float> beforeValues;
    unsigned changedFrames=0;
    void status(const char* event){
        if(id.empty())return;
        std::ofstream out("expression/"+id+".status",std::ios::app);
        out<<event<<" changed_frames="<<changedFrames<<"\n";
    }
public:
    int poll(int count){
        if(tracking||GetTickCount64()<nextPoll)return -1;
        nextPoll=GetTickCount64()+100;
        std::ifstream input("expression.ready",std::ios::binary|std::ios::ate);
        if(!input)return -1;
        const auto size=input.tellg();
        if(size<1||size>96){input.close();DeleteFileA("expression.ready");return -1;}
        input.seekg(0);
        std::string commandId,extra;
        int index=-1;
        bool valid=static_cast<bool>(input>>commandId>>index);
        if(input>>extra)valid=false;
        input.close();DeleteFileA("expression.ready");
        if(commandId.size()!=32||commandId.find_first_not_of("0123456789abcdef")!=std::string::npos)return -1;
        id=commandId;changedFrames=0;
        HANDLE claim=CreateFileA(("expression/"+id+".claimed").c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
        if(claim==INVALID_HANDLE_VALUE){status("claim_rejected");return -1;}
        CloseHandle(claim);
        if(!valid||index<0||index>=count){status("invalid_index");return -1;}
        return index;
    }
    bool validate(Live2D::Cubism::Framework::CubismModel* model,
                  Live2D::Cubism::Framework::CubismExpressionMotion* motion){
        indices.clear();
        if(!motion){status("expression_missing");return false;}
        const auto parameters=motion->GetExpressionParameters();
        if(parameters.GetSize()==0){status("expression_empty");return false;}
        for(int i=0;i<parameters.GetSize();++i){
            int found=-1;
            for(int p=0;p<model->GetParameterCount();++p)
                if(model->GetParameterId(p)==parameters[i].ParameterId){found=p;break;}
            if(found<0){status("parameter_missing");return false;}
            indices.push_back(found);
        }
        return true;
    }
    void started(bool ok){
        if(!ok){status("start_failed");return;}
        tracking=true;startedAt=GetTickCount64();changedFrames=0;status("started");
    }
    void before(Live2D::Cubism::Framework::CubismModel* model){
        if(!tracking)return;
        beforeValues.clear();
        for(int p:indices)beforeValues.push_back(model->GetParameterValue(p));
    }
    void after(Live2D::Cubism::Framework::CubismModel* model){
        if(!tracking)return;
        bool changed=false;
        for(size_t i=0;i<indices.size();++i)
            changed|=std::fabs(model->GetParameterValue(indices[i])-beforeValues[i])>0.0001f;
        if(changed)++changedFrames;
        if(GetTickCount64()-startedAt>=2000){
            status("evaluated");
            tracking=false;
        }
    }
};
