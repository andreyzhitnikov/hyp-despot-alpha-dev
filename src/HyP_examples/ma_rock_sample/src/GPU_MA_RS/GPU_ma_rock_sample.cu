#include "GPU_ma_rock_sample.h"
#include "base_ma_rock_sample.h"
#include "ma_rock_sample.h"
#include <bitset>
#include <despot/GPUutil/GPUrandom.h>
#include <despot/solver/Hyp_despot.h>

#include <despot/GPUinterface/GPUupper_bound.h>

using namespace std;

namespace despot {

/* =============================================================================
 * Dvc_MultiAgentRockSample class
 * =============================================================================*/
extern __shared__ int localParticles[];

__global__ void step_global( Dvc_State* vnode_particles,float* rand,
		float * reward, OBS_TYPE* obs, float* ub, Dvc_ValuedAction* lb,
		bool* term, int num_particles, int parent_action, Dvc_State* state)
{
	int action=blockIdx.x;
	int PID = (blockIdx.y * blockDim.x + threadIdx.x) ;
	if(PID<num_particles){
		int global_list_pos = action * num_particles + PID;
		float rand_num=rand[global_list_pos];

		if (threadIdx.y == 0) {
			DvcModelCopyToShared_(
				(Dvc_State*) ((int*) localParticles + 8 * threadIdx.x),
				vnode_particles, PID % num_particles, false);
		}
		Dvc_State* current_particle = (Dvc_State*) ((int*) localParticles + 8 * threadIdx.x);
		__syncthreads();


		term[global_list_pos]=DvcModelStep_(*current_particle, rand_num, parent_action, reward[global_list_pos], obs[global_list_pos]);

		if (blockIdx.y * blockDim.x + threadIdx.x < num_particles) {
			/*Record stepped particles from parent as particles in this node*/
			if (threadIdx.y == 0 && action==0) {
				Dvc_State* temp = DvcModelGet_(vnode_particles, PID % num_particles);
				DvcModelCopyNoAlloc_(temp, current_particle,0, false);
			}
		}

		term[global_list_pos]=DvcModelStep_(*current_particle, rand_num, action, reward[global_list_pos], obs[global_list_pos]);

		Dvc_History history;
		Dvc_RandomStreams streams;
		ub[global_list_pos]=DvcUpperBoundValue_(current_particle, 0, history);
		lb[global_list_pos]=DvcLowerBoundValue_(current_particle,streams,history, 0) ;

		Dvc_State* temp = DvcModelGet_(state, global_list_pos);
		DvcModelCopyNoAlloc_(temp, current_particle, 0, false);
	}
}


__global__ void step_global_1( Dvc_State* vnode_particles,float* rand,
		float * reward, OBS_TYPE* obs, float* ub, Dvc_ValuedAction* lb,
		bool* term, int num_particles, int parent_action, Dvc_State* state)
{
	int action=blockIdx.x;
	int PID = (blockIdx.y * blockDim.x + threadIdx.x) ;
	if(PID<num_particles){
		int global_list_pos = action * num_particles + PID;
		float rand_num=rand[global_list_pos];

		if (threadIdx.y == 0) {
			DvcModelCopyToShared_(
				(Dvc_State*) ((int*) localParticles + 8 * threadIdx.x),
				vnode_particles, PID % num_particles, false);
		}
		Dvc_State* current_particle = (Dvc_State*) ((int*) localParticles + 8 * threadIdx.x);
		__syncthreads();

		term[global_list_pos]=DvcModelStep_(*current_particle, rand_num, parent_action, reward[global_list_pos], obs[global_list_pos]);


		Dvc_State* temp = DvcModelGet_(state, global_list_pos);
		DvcModelCopyNoAlloc_(temp, current_particle, 0, false);
	}
}
__global__ void step_global_2( Dvc_State* vnode_particles,float* rand,
		float * reward, OBS_TYPE* obs, float* ub, Dvc_ValuedAction* lb,
		bool* term, int num_particles, int parent_action, Dvc_State* state)
{
	int action=blockIdx.x;
	int PID = (blockIdx.y * blockDim.x + threadIdx.x) ;
	if(PID<num_particles){
		int global_list_pos = action * num_particles + PID;
		float rand_num=rand[global_list_pos];

		if (threadIdx.y == 0) {
			DvcModelCopyToShared_(
				(Dvc_State*) ((int*) localParticles + 8 * threadIdx.x),
				state, global_list_pos, false);
		}
		Dvc_State* current_particle = (Dvc_State*) ((int*) localParticles + 8 * threadIdx.x);


		if (blockIdx.y * blockDim.x + threadIdx.x < num_particles) {
			/*Record stepped particles from parent as particles in this node*/
			if (threadIdx.y == 0 && action==0) {
				Dvc_State* temp = DvcModelGet_(vnode_particles, PID % num_particles);
				DvcModelCopyNoAlloc_(temp, current_particle,0, false);
			}
		}
		__syncthreads();


		term[global_list_pos]=DvcModelStep_(*current_particle, rand_num, action, reward[global_list_pos], obs[global_list_pos]);

		Dvc_History history;
		Dvc_RandomStreams streams;
		ub[global_list_pos]=DvcUpperBoundValue_(current_particle, 0, history);
		lb[global_list_pos]=DvcLowerBoundValue_(current_particle,streams,history, 0) ;

		Dvc_State* temp = DvcModelGet_(state, global_list_pos);
		DvcModelCopyNoAlloc_(temp, current_particle, 0, false);
	}
}

DEVICE bool Dvc_MultiAgentRockSample::Dvc_Step(Dvc_State& state, float rand_num, int action, float& reward,
			OBS_TYPE& obs)
{
	reward=0;
	obs=0;
	bool terminal=true;
	Dvc_MARockSampleState& rockstate = static_cast<Dvc_MARockSampleState&>(state);

	__syncthreads();
	unsigned long long int Temp=INIT_QUICKRANDSEED;
	for(int rid=0;rid<num_agents_;rid++)
	{
		SetRobObs(obs, E_NONE, rid);

		if(GetRobPosIndex(&rockstate, rid)!=ROB_TERMINAL_ID){

			int rob_act=GetRobAction(action, rid);
			//rob_act=Dvc_Compass::EAST;//debugging
			if (rob_act < E_SAMPLE) { // Move
				switch (rob_act) {
				case Dvc_Compass::EAST:
					if (GetX(&rockstate, rid) + 1 < ma_map_size_) {
						IncX(&rockstate, rid);
					} else {
						reward+= +10;
						SetRobPosIndex(rockstate.joint_pos, rid, ROB_TERMINAL_ID);
					}
					break;

				case Dvc_Compass::NORTH:
					if (GetY(&rockstate, rid) + 1 < ma_map_size_)
						IncY(&rockstate, rid);
					else{
						reward += -100;
					}
					break;

				case Dvc_Compass::SOUTH:
					if (GetY(&rockstate, rid) - 1 >= 0)
						DecY(&rockstate, rid);
					else
						reward += -100;
					break;

				case Dvc_Compass::WEST:
					if (GetX(&rockstate, rid) - 1 >= 0)
						DecX(&rockstate, rid);
					else
						reward += -100;
					break;
				}
			}
			if (rob_act == E_SAMPLE) { // Sample
				int rock = ma_grid_[GetRobPosIndex(&rockstate, rid)];
				if (rock >= 0) {
					if (GetRock(&rockstate, rock))
						reward += +10;
					else
						reward += -10;
					SampleRock(&rockstate, rock);
				} else {
					reward += -100;
				}
			}

			if (rob_act > E_SAMPLE) { // Sense
				int rob_obs = 0;
				int rock = (rob_act - E_SAMPLE - 1) % ma_num_rocks_;
				float distance = DvcCoord::EuclideanDistance(GetRobPos(&rockstate, rid),
					ma_rock_pos_[rock]);
				int action_type = (rob_act - E_SAMPLE - 1)/ma_num_rocks_;
				reward = action_type*(-0.01);
				double half_efficiency_distance = action_type > 0 ? ma_half_efficiency_distance_2_ : ma_half_efficiency_distance_;
				float efficiency = (1 + pow(2, -distance / half_efficiency_distance))
					* 0.5;

				//float efficiency = (1 + powf(2, -distance / ma_half_efficiency_distance_))
				//	* 0.5;
				if(use_continuous_observation)
				{
					bool good_rock = GetRock(&rockstate, rock);
					if(efficiency > (1-continuous_observation_interval))
					{
						efficiency = (1-continuous_observation_interval);
					}
					float prob_bucket_double = rand_num * continuous_observation_scale;
					int prob_bucket = (int)prob_bucket_double;
					float remaining_prob = prob_bucket_double - prob_bucket;
					float prob_good = efficiency + (continuous_observation_interval*(float)prob_bucket / (float)continuous_observation_scale);

						if(remaining_prob > prob_good)
						{
							prob_good = 1-prob_good;
						}
						if(!good_rock & E_GOOD)
						{
							prob_good = 1-prob_good;
						}

						//double real_obs = (random_num*(upper_limit-lower_limit)) + lower_limit;
						rob_obs = int(prob_good*continuous_observation_scale/continuous_observation_interval);
						SetRobObs(obs, rob_obs, rid);
				}
				else
				{
					for(int j = 0; j < num_obs_bits; j++)
					{int temp_rob_obs;

						if (rand_num < efficiency)
							temp_rob_obs= GetRock(&rockstate, rock) & E_GOOD;
						else
							temp_rob_obs= !(GetRock(&rockstate, rock) & E_GOOD);
						rob_obs = (2*rob_obs + temp_rob_obs);
						rand_num=Dvc_QuickRandom::RandGeneration(&Temp, rand_num);
					}
					rob_obs = 4*rob_obs;
					SetRobObs(obs, rob_obs, rid);
					//if (rand_num < efficiency)
					//	SetRobObs(obs, GetRock(&rockstate, rock) & E_GOOD, rid);
					//else
					//	SetRobObs(obs, !(GetRock(&rockstate, rock) & E_GOOD), rid);
				}
			}


			if (GetRobPosIndex(&rockstate, rid)!=ROB_TERMINAL_ID) {
				terminal=false;
			}
		}
	}

	if(GPUDoPrint/* && action==blockIdx.x*/)
			printf("(GPU_step) action %d scenario %d state_id %d joint_pos %d blockid.y %d threadid.x %d rand %f\n",
				action, rockstate.scenario_id, rockstate.state_id, rockstate.joint_pos, blockIdx.y, threadIdx.x, rand_num);

	return terminal;
}
DEVICE float Dvc_MultiAgentRockSample::Dvc_ObsProb(OBS_TYPE& obs, Dvc_State& state, int action)
{
	float prob=1;
	//calculate prob for each robot, multiply them together
		for(int i=0;i<num_agents_;i++){
			int agent_action=GetRobAction(action, i);
			int rob_obs= GetRobObs(obs, i);
			const Dvc_MARockSampleState& rockstate =
				static_cast<const Dvc_MARockSampleState&>(state);
			if(GetRobPosIndex(&rockstate, i)!=ROB_TERMINAL_ID){
				if (agent_action <= E_SAMPLE)
					prob *= (rob_obs == E_NONE);
				//else if (rob_obs < 4) //Last 2 bits for E_NONE
				//	prob *=0;
				else{
					//int rock = agent_action - E_SAMPLE - 1;
					int rock = (agent_action - E_SAMPLE - 1) % ma_num_rocks_;
					float distance = DvcCoord::EuclideanDistance(GetRobPos(&rockstate, i),
						ma_rock_pos_[rock]);
					float efficiency = (1 + pow(2, -distance / ma_half_efficiency_distance_))
						* 0.5;
					int true_state = (GetRock(&rockstate, rock) & 1);
					if(use_continuous_observation)
					{
						float obs_prob = (continuous_observation_interval*rob_obs)/(continuous_observation_scale);
						prob *= (true_state == E_BAD ? (1-obs_prob):obs_prob);
					}
					else
					{
						for(int j = 0; j < num_obs_bits; j++)
						{
							int my_rob_obs = (rob_obs >> (2+j)) & 1;
							prob*= ( true_state== my_rob_obs) ? efficiency : (1 - efficiency);
							if(j % 8 == 0)
							{
								prob = prob*1000; //Multiply by a constant to avoid prob becoming 0
							}
						}
					}
				}
			}
		}
		return prob;

}
DEVICE int Dvc_MultiAgentRockSample::NumActions()
{

		return pow((float)((num_action_types*ma_num_rocks_) + 5), num_agents_);

}


DEVICE int Dvc_MultiAgentRockSample::Dvc_NumObservations()
{
	return /*3*/num_agents_*(1 + (1 << num_obs_bits));
}
DEVICE Dvc_State* Dvc_MultiAgentRockSample::Dvc_Get(Dvc_State* particles, int pos)
{
	Dvc_MARockSampleState* particle_i= static_cast<Dvc_MARockSampleState*>(particles)+pos;

	return particle_i;
}
DEVICE void Dvc_MultiAgentRockSample::Dvc_Copy_NoAlloc(Dvc_State* des, const Dvc_State* src, int pos, bool offset_des)
{
	/*Pass member values, assign member pointers to existing state pointer*/
	const Dvc_MARockSampleState* src_i= static_cast<const Dvc_MARockSampleState*>(src)+pos;
	if(!offset_des) pos=0;
	Dvc_MARockSampleState* des_i= static_cast<const Dvc_MARockSampleState*>(des)+pos;

	des_i->weight = src_i->weight;
	des_i->scenario_id = src_i->scenario_id;
	des_i->state_id = src_i->state_id;
	des_i->joint_pos = src_i->joint_pos;

	//des_i->allocated_=true;
}

} // namespace despot
