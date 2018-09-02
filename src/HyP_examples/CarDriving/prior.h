#ifndef PRIOR_H
#define PRIOR_H
#include <despot/planner.h>

using namespace std;

using namespace despot;
/* =============================================================================
 * SolverPrior class
 * =============================================================================*/

class SolverPrior {
protected:
	const DSPOMDP* model_;
	ActionStateHistory as_history_;
	VariableActionStateHistory as_history_in_search_;
	std::vector<double> action_probs_;

public:
	SolverPrior(const DSPOMDP* model):model_(model){;}
	virtual ~SolverPrior(){;}

	inline virtual int SmartCount(ACT_TYPE action) const {
		return 10;
	}

	inline virtual double SmartValue(ACT_TYPE action) const {
		return 1;
	}

	inline virtual const ActionStateHistory& history() const {
		return as_history_;
	}

	inline virtual VariableActionStateHistory& history_in_search() {
		return as_history_in_search_;
	}

	inline virtual void history_in_search(VariableActionStateHistory h) {
		as_history_in_search_ = h;
	}

	inline virtual void history(ActionStateHistory h) {
		as_history_ = h;
	}

	inline const std::vector<const State*>& history_states() {
		return as_history_.states();
	}

	inline std::vector<State*>& history_states_for_search() {
		return as_history_in_search_.states();
	}

	inline virtual void Add(ACT_TYPE action, const State* state) {
		as_history_.Add(action, state);
	}
	inline virtual void Add_in_search(ACT_TYPE action, State* state) {
		as_history_in_search_.Add(action, state);
	}

	inline virtual void PopLast(bool insearch) {
		(insearch)? as_history_in_search_.RemoveLast(): as_history_.RemoveLast();
	}

    inline virtual void PopAll(bool insearch) {
	  (insearch)? as_history_in_search_.Truncate(0): as_history_.Truncate(0);
	}

	virtual const std::vector<double>& ComputePreference(const Belief* belief, const State* state) = 0;

	virtual double ComputeValue(const Belief* belief, const State* state,std::vector<int>& rollout_scenarios,
			RandomStreams& streams, VNode* vnode)=0;
	const std::vector<double>& action_probs() const;
};

#endif
