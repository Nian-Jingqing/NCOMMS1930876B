function[mvpaout] = parse_mvpa_results_operation_four(args, ph, dirs, check_perf)

%---------------------------------------------------------------------------
%***************** parse the results
%---------------------------------------------------------------------------
%***************** the volume was shifted: no shift for the regressor
%***************** trial: 0_FIX, each trial: stim (6+6 tr) + iti (5:9 tr)
%***************** presentation 6s: 1_stim, 2_manip  ulation, 0_fixation
%***************** manipulation 6s: 0_stim, 1_instruction + fixation
%***************** check_perf: 1_check total performance for penalty check

xph = args.xphase;
fprintf('\n(+) parse the results: %s\n', args.phase_name{xph});

xindex   = args.index{xph};% param index from study
xparam   = xindex.param;

n_target = size(ph.results.iterations(1).acts, 1);%
n_iter   = size(ph.results.iterations, 2);
for xiter = 1:n_iter
    t_vol(xiter) = size(ph.results.iterations(xiter).acts, 2);
end
n_vols = sum(t_vol);

%***************** unpack parameters
if args.four_oper_regress
    it_conds = [1 2 4 5];
else
    it_conds = 1:5;
end

n_condition    = length(it_conds);
condition_name = cell(1, n_condition);

for it = 1:n_condition
    xcond = it_conds(it);
    condition_name{it} = xparam.conds_names{xcond};
end

if n_condition ~= n_target
    fprintf('!!!!! the number of targets are wrong!\n')
end

%% ***************** reset regs
xregs.runs         = args.regs{xph}.selectors;
xregs.timecourse   = zeros(1, n_vols);
xregs.operation_sh = zeros(1, n_vols);%only operation window

for it = 1:n_condition
    xcond = it_conds(it);
    xunit = getDATA(xindex.matrix', xindex.header, {'condition'}, {xcond});
    
    xregs.timecourse(xunit) = xcond;
    
    xunit = find(getDATA(xindex.matrix', xindex.header, ...
        {'condition','manipulation','spike'}, ...
        {xcond, 1, 0}));
    
    xregs.operation_sh(xunit + args.shift_TRs) = it;
end

%% ============= UNPACK PARAMETERS
n_validation = numel(ph.results.iterations);
n_runs       = xparam.n_runs;
n_trials     = xparam.n_trials;
n_trs        = args.tc_tr;

%*************** output basename
base_name    = args.analysis_basename;

%% ============= CLASSIFICATION RESULTS
% xdesired: 1_5 operations, 6: perception, 7: rest
% decode.classifier.guessed{xdesired}(xguess)
% decode.classifier.evidence{xdesired}(xguess)
% decode.classifier.accuracy(xdesired)
% out_guess, out_acts
% ph.results.iterations(i).test_idx = i run

for xiter = 1:n_validation
    %*************** desired from regressor
    out_desireds = xregs.operation_sh(xregs.runs == xiter);
    
    %*************** pfmet: based on shifted regressor / (startTR:end)
    out_guesses  = ph.results.iterations(xiter).perfmet.guesses;
    out_acts     = ph.results.iterations(xiter).acts;
    
    %*************** correctness
    iter_perf = [];
    
    for xcond = 1:n_target
        xunit     = out_desireds==xcond;
        xguesses  = out_guesses(xunit);
        xacts     = out_acts(:,xunit);
        
        for xguess=1:n_target
            decode.classifier.guessed{xcond}(xiter,xguess)  = numel(find(xguesses == xguess));
            decode.classifier.evidence{xcond}(xiter,xguess) = mean(xacts(xguess,:));
        end
        
        decode.classifier.accuracy{xcond}(xiter) = mean(xguesses==xcond);
        iter_perf = horzcat(iter_perf, mean(xguesses==xcond));
    end
    
    decode.classifier.iteration{xiter}.accuracy = mean(iter_perf);
end

%% ============= PARSE THE DECODING RESULTS
if check_perf% check mvpa performance
    
    %% ============= ANALYSIS PARAMETERS
    %*************** selected volxels
    n_total_voxels = ph.param.n_total_voxels;
    n_voxels       = ph.param.n_voxels;
    n_percent      = ph.param.n_percent;
    
    %% ============= WRITE TABLE TO CSV FILES FOR PYTHON
    clear xaccuracy xevidence targ_accuracy
    
    %*************** create tables
    for xcond = 1:n_target
        clear n_total tacc tevi
        
        guess_names(xcond)     = strcat(sprintf('g%s_', num2str(xcond)), condition_name(xcond));
        target_names(xcond)    = strcat(sprintf('t%s_', num2str(xcond)), condition_name(xcond));
        
        for xiter = 1:n_validation    
            n_total            = sum(decode.classifier.guessed{xcond}(xiter,:));
            
            tacc(xiter,:)      = decode.classifier.guessed{xcond}(xiter,:)/n_total;
            tevi(xiter,:)      = decode.classifier.evidence{xcond}(xiter,:);
        end
        
        xaccuracy(xcond,:)     = mean(tacc); %#ok<*AGROW>
        xevidence(xcond,:)     = mean(tevi);
        targ_accuracy{xcond+1} = xaccuracy(xcond, xcond);%target accuracy
        targ_evidence{xcond+1} = xevidence(xcond, xcond);%target accuracy
    end
    
    %*************** create tables
    table_accuracy = array2table(xaccuracy,...
        'RowNames', target_names, 'VariableNames', guess_names);
    
    table_evidence = array2table(xevidence,...
        'RowNames', target_names, 'VariableNames', guess_names);
    
    targ_accuracy{1}     = args.subject_id;
    targ_accuracy{end+1} = mean([targ_accuracy{2:length(condition_name)+1}]);
    targ_accuracy{end+1} = ph.args.xpenalty;
    targ_accuracy{end+1} = n_total_voxels;
    targ_accuracy{end+1} = n_voxels;
    targ_accuracy{end+1} = n_percent;
    
    targ_evidence{1}     = args.subject_id;
    
    table_targ_accuracy  = cell2table(targ_accuracy, 'VariableNames', ...
        horzcat('subject_id', target_names, 'total_accuracy','penalty',...
        'total_voxels', 'selected_voxels', 'percentage'));
    
    table_targ_evidence  = cell2table(targ_evidence, 'VariableNames', ...
        horzcat('subject_id', target_names));
    
    %*************** write tables to csv files
    csv_name = sprintf('%s/table_accuracy_%s.csv', dirs.mvpa.parse{xph}, base_name);
    writetable(table_accuracy, csv_name,'WriteRowNames',true)
    
    csv_name = sprintf('%s/table_evidence_%s.csv', dirs.mvpa.parse{xph}, base_name);
    writetable(table_evidence, csv_name,'WriteRowNames',true)
    
    csv_name = sprintf('%s/table_target_accuracy_%s.csv', dirs.mvpa.parse{xph}, base_name);
    writetable(table_targ_accuracy, csv_name,'WriteRowNames',true)
    
    csv_name = sprintf('%s/table_target_evidence_%s.csv', dirs.mvpa.parse{xph}, base_name);
    writetable(table_targ_evidence, csv_name,'WriteRowNames',true)
    
    %*************** selected volxels
    table_selected_voxels = table(n_total_voxels, n_voxels, n_percent, ...
        'VariableNames', {'total_voxels', 'selected_voxels', 'percentage'}');
    
    csv_name = sprintf('%s/table_n_voxels_%s.csv', dirs.mvpa.parse{xph}, base_name);
    writetable(table_selected_voxels, csv_name,'WriteRowNames',true)
    
    %% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %*************** TIMECOURSE
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%    
    xheader = xindex.header;
    xmatrix = xindex.matrix;
    
    %% ============= EXTRACTING EVIDENCE
    %*************** decode.timecourse.operation{xcond}.target{xtarg}.evidence{xtr}
    %*************** operation: maintain/ replace_category/ replace_subcategory/
    %***************            target_suppress/ global_clear
    %*************** xtarg: 1_targ, 2_nontarg
    clear out_acts 
    for zz = 1:2, out_acts{zz} = []; end
    
    for xrun = 1:n_runs
        out_acts{1} = horzcat(out_acts{1}, ph.results.iterations(xrun).acts);
        
        %*************** zscoring within each class
        clear t_out_acts_z
        for xact = 1:n_target
            t_out_acts_z(xact, :) = zscore(ph.results.iterations(xrun).acts(xact,:));
        end
        out_acts{2} = horzcat(out_acts{2}, t_out_acts_z);
    end
    
    %% ============= EXTRACTING EVIDENCE: SEPARATED OPERATIONS
    %*************** decode.timecourse.operation{xcond}.decoded_operation{xoper}.evidence{xtr}
    %*************** operation: maintain/ replace_category/ replace_subcategory/
    %***************            target_suppress/ global_clear
    %*************** xtarg: 1_targ, 2_nontarg
    
    for xcond = 1:n_condition
        for xoper = 1:n_condition
            for xtr = 1:n_trs
                for zz = 1:2%1_raw, 2_zscored
                    decode.timecourse.operation{xcond}.decoded_operation{xoper}.evidence{zz}.tr{xtr} = [];
                    
                    if xtr <= dur_sync
                        decode.timecourse.sync.operation{xcond}.decoded_operation{xoper}.evidence{zz}.tr{xtr} = [];
                    end
                end
            end
        end
    end
    
    %*************** evidence
    for xrun = 1:n_runs
        for xtrial = 1:n_trials(xrun)
            xunit    = find(getDATA(xmatrix', xheader, {'run','trial'}, {xrun, xtrial}));
            xcond    = unique(xmatrix(findCol(xheader, {'condition'}), xunit));
            
            it       = find(it_conds==xcond);
            if sum(it)
                xunit_tc = xunit(1):(xunit(1) + n_trs - 1);
                xspike   = ~(xmatrix(findCol(xheader, {'spike'}), xunit_tc));
                
                if sum(xspike)~=0
                    for xtr = 1:length(xunit_tc)
                        if xspike(xtr)
                            for xoper = 1:n_condition
                                for zz = 1:2
                                    decode.timecourse.operation{it}.decoded_operation{xoper}.evidence{zz}.tr{xtr} = ...
                                        horzcat(decode.timecourse.operation{it}.decoded_operation{xoper}.evidence{zz}.tr{xtr}, ...
                                        out_acts{zz}(xoper, xunit_tc(xtr)));
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    %% ============= PACK MVPAOUT
    decode.header  = xheader;
    decode.matrix  = xmatrix;

end

mvpaout.decode = decode;

end
