#include "GPU_Init.h"

#include <despot/GPUconfig.h>
#include <despot/GPUcore/CudaInclude.h>
#include <despot/GPUcore/GPUglobals.h>
#include <despot/GPUcore/GPUbuiltin_lower_bound.h>
#include <despot/GPUcore/GPUbuiltin_policy.h>


#include "GPU_Car_Drive.h"
#include "GPU_CarUpperBound.h"
#include "GPU_LowerBoundPolicy.h"

#include <despot/solver/Hyp_despot.h>

#include <ped_pomdp.h>
#include <vector>
#include <simulator.h>
using namespace despot;
using namespace std;

static Dvc_PedPomdp* Dvc_pomdpmodel=NULL;
static Dvc_PedPomdpParticleLowerBound* b_smart_lowerbound=NULL;
static Dvc_PedPomdpParticleUpperBound1* upperbound=NULL;
static Dvc_PedPomdpSmartPolicy* smart_lowerbound=NULL;
static Dvc_PedPomdpDoNothingPolicy* do_nothing_lowerbound=NULL;

static Dvc_COORD* tempGoals=NULL;
static Dvc_COORD* tempPath=NULL;


void UpdateGPUGoals(DSPOMDP* Hst_model);
void UpdateGPUPath(DSPOMDP* Hst_model);

__global__ void PassPedPomdpFunctionPointers(Dvc_PedPomdp* model)
{
	DvcModelStepIntObs_=&(model->Dvc_Step);
	DvcModelObsProbIntObs_=&(model->Dvc_ObsProbInt);
	DvcModelCopyNoAlloc_=&(model->Dvc_Copy_NoAlloc);
	DvcModelCopyToShared_=&(model->Dvc_Copy_ToShared);
	DvcModelGet_=&(model->Dvc_Get);
	//DvcModelGetBestAction_=&(model->Dvc_GetBestAction);
	DvcModelGetMaxReward_=&(model->Dvc_GetMaxReward);
	DvcModelNumActions_ = &(model->NumActions);
}

__global__ void PassPedPomdpParams(	double _in_front_angle_cos, double _freq,
		Dvc_COORD* _goals, Dvc_COORD* _path, int pathsize,
		double GOAL_TRAVELLED,
		int N_PED_IN,
		int N_PED_WORLD,
		double VEL_MAX,
		double NOISE_GOAL_ANGLE,
		double CRASH_PENALTY,
		double REWARD_FACTOR_VEL,
		double REWARD_BASE_CRASH_VEL,
		double BELIEF_SMOOTHING,
		double NOISE_ROBVEL,
		double COLLISION_DISTANCE,
		double IN_FRONT_ANGLE_DEG,
		double LASER_RANGE,
		double pos_rln, // position resolution
		double vel_rln, // velocity resolution
		double PATH_STEP,
		double GOAL_TOLERANCE,
		double PED_SPEED,
		bool debug,
		double control_freq,
		double AccSpeed,
		double GOAL_REWARD)
{
	in_front_angle_cos=_in_front_angle_cos;
	freq=_freq;
	goals=_goals;
	if(path == NULL) path=new Dvc_Path();


	Dvc_ModelParams::GOAL_TRAVELLED =  GOAL_TRAVELLED ;
	Dvc_ModelParams::N_PED_IN = N_PED_IN  ;
	Dvc_ModelParams::N_PED_WORLD = N_PED_WORLD  ;
	Dvc_ModelParams::VEL_MAX =  VEL_MAX ;
	Dvc_ModelParams::NOISE_GOAL_ANGLE = NOISE_GOAL_ANGLE  ;
	Dvc_ModelParams::CRASH_PENALTY =  CRASH_PENALTY ;
	Dvc_ModelParams::REWARD_FACTOR_VEL = REWARD_FACTOR_VEL  ;
	Dvc_ModelParams::REWARD_BASE_CRASH_VEL =  REWARD_BASE_CRASH_VEL ;
	Dvc_ModelParams::BELIEF_SMOOTHING =   BELIEF_SMOOTHING;
	Dvc_ModelParams::NOISE_ROBVEL =NOISE_ROBVEL;
	Dvc_ModelParams::COLLISION_DISTANCE =  COLLISION_DISTANCE ;
	Dvc_ModelParams::IN_FRONT_ANGLE_DEG = IN_FRONT_ANGLE_DEG  ;
	Dvc_ModelParams::LASER_RANGE =  LASER_RANGE ;
	Dvc_ModelParams::pos_rln =  pos_rln ; // position resolution
	Dvc_ModelParams::vel_rln =  vel_rln ; // velocity resolution
	Dvc_ModelParams::PATH_STEP =  PATH_STEP ;
	Dvc_ModelParams::GOAL_TOLERANCE =  GOAL_TOLERANCE ;
	Dvc_ModelParams::PED_SPEED = PED_SPEED  ;
	Dvc_ModelParams::debug =  debug ;
	Dvc_ModelParams::control_freq =  control_freq ;
	Dvc_ModelParams::AccSpeed =  AccSpeed ;
	Dvc_ModelParams::GOAL_REWARD = GOAL_REWARD  ;
	printf("pass model to gpu\n");
	 
}

__global__ void UpdatePathKernel(Dvc_COORD* _path, int pathsize)
{
	if(path) {delete path; path=new Dvc_Path();}
	if(path==NULL) 	path=new Dvc_Path();

	path->size_=pathsize;
	path->pos_=0;
	path->way_points_=_path;
	printf("pass path to gpu %d\n", path);
}

void PedPomdp::InitGPUModel(){
	PedPomdp* Hst =static_cast<PedPomdp*>(this);


	HANDLE_ERROR(cudaMallocManaged((void**)&Dvc_pomdpmodel, sizeof(Dvc_PedPomdp)));

	PassPedPomdpFunctionPointers<<<1,1,1>>>(Dvc_pomdpmodel);
	HANDLE_ERROR(cudaDeviceSynchronize());

	logd <<"Hst->world_model->path.size()= "<< Hst->world_model->path.size()<< endl;

	if(tempPath==NULL && Hst->world_model->path.size()>0){

		HANDLE_ERROR(cudaMallocManaged((void**)&tempPath, Hst->world_model->path.size()*sizeof(Dvc_COORD)));
	}
	if(tempGoals==NULL && Hst->world_model->goals.size()>0)
	HANDLE_ERROR(cudaMallocManaged((void**)&tempGoals,  Hst->world_model->goals.size()*sizeof(Dvc_COORD)));

	

	PassPedPomdpParams<<<1,1,1>>>(
		Hst->world_model->in_front_angle_cos, Hst->world_model->freq, tempGoals, tempPath,Hst->world_model->path.size(),
		ModelParams::GOAL_TRAVELLED,
		ModelParams::N_PED_IN,
		ModelParams::N_PED_WORLD,
		ModelParams::VEL_MAX,
		ModelParams::NOISE_GOAL_ANGLE,
		ModelParams::CRASH_PENALTY,
		ModelParams::REWARD_FACTOR_VEL,
		ModelParams::REWARD_BASE_CRASH_VEL,
		ModelParams::BELIEF_SMOOTHING,
		ModelParams::NOISE_ROBVEL,
		ModelParams::COLLISION_DISTANCE,
		ModelParams::IN_FRONT_ANGLE_DEG,
		ModelParams::LASER_RANGE,
		ModelParams::pos_rln, // position resolution
		ModelParams::vel_rln, // velocity resolution
		ModelParams::PATH_STEP,
		ModelParams::GOAL_TOLERANCE,
		ModelParams::PED_SPEED,
		ModelParams::debug,
		ModelParams::control_freq,
		ModelParams::AccSpeed,
		ModelParams::GOAL_REWARD);
	
	HANDLE_ERROR(cudaDeviceSynchronize());

	UpdateGPUGoals(Hst);
	UpdateGPUPath(Hst);

	HANDLE_ERROR(cudaDeviceSynchronize());

}

__global__ void PassActionValueFuncs(
		Dvc_PedPomdpParticleUpperBound1* upperbound)
{
	DvcUpperBoundValue_ = &(upperbound->Value);
}

void PedPomdp::InitGPUUpperBound(string name,
		string particle_bound_name) const{
	HANDLE_ERROR(cudaMalloc((void**)&upperbound, sizeof(Dvc_PedPomdpParticleUpperBound1)));

	PassActionValueFuncs<<<1,1,1>>>(upperbound);

	HANDLE_ERROR(cudaDeviceSynchronize());
}



__global__ void PassPedPomdpPolicyFuncPointers(Dvc_PedPomdpSmartPolicy* lowerbound)
{
	DvcDefaultPolicyAction_=&(lowerbound->Action);
	DvcLowerBoundValue_=&(lowerbound->Value);
}

__global__ void PassPedPomdpPolicyFuncPointers(Dvc_PedPomdpDoNothingPolicy* lowerbound)
{
	DvcDefaultPolicyAction_=&(lowerbound->Action);
	DvcLowerBoundValue_=&(lowerbound->Value);
}

__global__ void PassPedPomdpPlbFuncPointers(Dvc_PedPomdpParticleLowerBound* b_lowerbound)
{
	DvcParticleLowerBound_Value_=&(b_lowerbound->Value);
}


void PedPomdp::InitGPULowerBound(string name,
		string particle_bound_name) const{
	if(name=="DONOTHING")
	{
		HANDLE_ERROR(cudaMallocManaged((void**)&do_nothing_lowerbound, sizeof(Dvc_PedPomdpDoNothingPolicy)));

		PassPedPomdpPolicyFuncPointers<<<1,1,1>>>(do_nothing_lowerbound);
	}
	else
	{
		HANDLE_ERROR(cudaMallocManaged((void**)&smart_lowerbound, sizeof(Dvc_PedPomdpSmartPolicy)));

		PassPedPomdpPolicyFuncPointers<<<1,1,1>>>(smart_lowerbound);
	}
	HANDLE_ERROR(cudaDeviceSynchronize());

	HANDLE_ERROR(cudaMallocManaged((void**)&b_smart_lowerbound, sizeof(Dvc_PedPomdpParticleLowerBound)));

	PassPedPomdpPlbFuncPointers<<<1,1,1>>>(b_smart_lowerbound);

	HANDLE_ERROR(cudaDeviceSynchronize());
}




void PedPomdp::DeleteGPUModel()
{
	  HANDLE_ERROR(cudaFree(Dvc_pomdpmodel));

	  if(tempGoals)HANDLE_ERROR(cudaFree(tempGoals));
	  if(tempPath)HANDLE_ERROR(cudaFree(tempPath));
}

void PedPomdp::DeleteGPUUpperBound(string name,
		string particle_bound_name)
{
	  HANDLE_ERROR(cudaFree(upperbound));
}

void PedPomdp::DeleteGPULowerBound(string name,
		string particle_bound_name)
{
	  if(smart_lowerbound)HANDLE_ERROR(cudaFree(smart_lowerbound));
	  if(do_nothing_lowerbound) HANDLE_ERROR(cudaFree(do_nothing_lowerbound));
	  if(b_smart_lowerbound)HANDLE_ERROR(cudaFree(b_smart_lowerbound));
}

__global__ void UpdateGoalKernel(Dvc_COORD* _goals)
{
	goals=_goals;
}

void UpdateGPUGoals(DSPOMDP* Hst_model)
{
	if(Globals::config.useGPU){
		PedPomdp* Hst =static_cast<PedPomdp*>(Hst_model);
		if(tempGoals)HANDLE_ERROR(cudaFree(tempGoals));

		cout << __FUNCTION__ << "@" << __LINE__ << endl;
		cout << "goal list size: " << Hst->world_model->goals.size()<< endl;
		HANDLE_ERROR(cudaMallocManaged((void**)&tempGoals,  Hst->world_model->goals.size()*sizeof(Dvc_COORD)));


		for(int i=0;i<Hst->world_model->goals.size();i++){
			tempGoals[i].x=Hst->world_model->goals[i].x;
			tempGoals[i].y=Hst->world_model->goals[i].y;
		}
		UpdateGoalKernel<<<1,1,1>>>(tempGoals);
		HANDLE_ERROR(cudaDeviceSynchronize());
	}

}

void UpdateGPUPath(DSPOMDP* Hst_model)
{

	if(Globals::config.useGPU){
		PedPomdp* Hst =static_cast<PedPomdp*>(Hst_model);

		if(tempPath)HANDLE_ERROR(cudaFree(tempPath));
		HANDLE_ERROR(cudaMallocManaged((void**)&tempPath, Hst->world_model->path.size()*sizeof(Dvc_COORD)));

		for(int i=0;i<Hst->world_model->path.size();i++){
			tempPath[i].x=Hst->world_model->path[i].x;
			tempPath[i].y=Hst->world_model->path[i].y;
		}

		UpdatePathKernel<<<1,1,1>>>(tempPath,Hst->world_model->path.size());
		HANDLE_ERROR(cudaDeviceSynchronize());
	}
	//exit(-1);
}
