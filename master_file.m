addpath(genpath('C:\bin\GitHub\KiloSort'))
addpath(genpath('C:\bin\GitHub\npy-matlab'))

% addpath('C:\Users\Marius\Documents\GitHub\npy-matlab')
ops.verbose             = 1;
ops.showfigures         = 1;

ops.root                = 'C:\DATA\Spikes\Piroska'; %'C:\DATA\Spikes\20150601_chan32_4_900s';
ops.fidname             = 'piroska_example'; % '20150601_all_GT91_4_900';
ops.datatype            = 'openEphys'; % 'raw', 'openEphys'
ops.fs                  = 25000; % sampling rate
ops.NchanTOT            = 32; %384;   % total number of channels
ops.Nchan               = 32; %374;   % number of active channels 
ops.Nfilt               = 64 ; %  number of filters to use (512, should be a multiple of 32)     
ops.nNeighPC            = 12; %visualization only: number of channnels to mask the PCs, leave empty to skip (12)
ops.nNeigh              = 16; %visualization only: number of neighboring templates to retain projections of (16)

% options for channel whitening
ops.whitening           = 'full'; % type of whitening (default 'full', for 'noSpikes' set options for spike detection below)
ops.nSkipCov            = 1; % compute whitening matrix from every N-th batch
ops.whiteningRange      = 32; % how many channels to whiten together (Inf for whole probe whitening, should be fine if Nchan<=32)

% define the channel map as a filename (string) or simply an array
ops.chanMap = 'C:\DATA\Spikes\Piroska\chanMap.mat';
% ops.chanMap = 1:ops.Nchan; %'C:\DATA\Spikes\20150601_chan32_4_900s\chanMap.mat'; %1:ops.Nchan; %'C:\DATA\Spikes\forPRBimecToWhisper.mat';
%     ops.chanMap = 'C:\DATA\Spikes\set8\forPRBimecP3opt3.mat';

% other options for controlling the model and optimization
ops.Nrank               = 3;    % matrix rank of spike template model (3)
ops.nfullpasses         = 6;    % number of complete passes through data during optimization (6)
ops.maxFR               = 20000;  % maximum number of spikes to extract per batch (20000)
ops.fshigh              = 300;   % frequency for high pass filtering
ops.ntbuff              = 64;    % samples of symmetrical buffer for whitening and spike detection
ops.scaleproc           = 200;   % int16 scaling of whitened data
ops.NT                  = 32*1024+ ops.ntbuff;% this is the batch size, very important for memory reasons. 
% should be multiple of 32 (or higher power of 2) + ntbuff

% these options can improve/deteriorate results. 
% when multiple values are provided for an option, the first two are beginning and ending anneal values, 
% the third is the value used in the final pass. 
ops.Th               = [4 12 12];    % threshold for detecting spikes on template-filtered data ([6 12 12])
ops.lam              = [5 20 20];   % large means amplitudes are forced around the mean ([10 30 30])
ops.nannealpasses    = 4;            % should be less than nfullpasses (4)
ops.momentum         = 1./[20 400];  % start with high momentum and anneal (1./[20 1000])
ops.shuffle_clusters = 1;            % allow merges and splits during optimization (1)
ops.mergeT           = .1;           % upper threshold for merging (.1)
ops.splitT           = .1;           % lower threshold for splitting (.1)

% options for initializing spikes from data
ops.initialize      = 'no'; %'fromData' or 'no'
ops.spkTh           = -6;      % spike threshold in standard deviations (4)
ops.loc_range       = [3  1];  % ranges to detect peaks; plus/minus in time and channel ([3 1])
ops.long_range      = [30  6]; % ranges to detect isolated peaks ([30 6])
ops.maskMaxChannels = 5;       % how many channels to mask up/down ([5])
ops.crit            = .65;     % upper criterion for discarding spike repeates (0.65)
ops.nFiltMax        = 10000;   % maximum "unique" spikes to consider (10000)

% load predefined principal components 
dd                  = load('PCspikes2.mat'); % you might want to recompute this from your own data
ops.wPCA            = dd.Wi(:,1:7);   % PCs 

% options for posthoc merges (under construction)
ops.fracse  = 0.1; % binning step along discriminant axis for posthoc merges (in units of sd)
ops.epu     = Inf;

ops.ForceMaxRAMforDat   = 20e9; %0e9;  % maximum RAM the algorithm will try to use
ops.GPU                 = 0;


%%

clearvars -except fidname ops idset  tClu tRes time_run dd

if strcmp(ops.datatype , 'openEphys')
   ops = convertOpenEphysToRawBInary(ops); 
end
%%
fname       = fullfile(ops.root, sprintf('%s.dat', ops.fidname)); % full path to file
fnameTW     = fullfile(ops.root, 'temp_wh.dat'); % (residual from RAM) of whitened data

% high-pass, whiten and load data into RAM (+ residual data on disk)
load_data_and_PCproject;

% do scaled kmeans to initialize the algorith,
if strcmp(ops.initialize, 'fromData')
    optimizePeaks;
end

% iterate the template matching algorithm
run_reg_mu2; 

%% extracts final spike times (overlapping extraction)
fullMPMU; 

% posthoc merge templates (under construction)
%     rez = merge_posthoc2(rez);

% save matlab results file
save(fullfile(ops.root,  'rez.mat'), 'rez');

% save python results file for Phy
rezToPhy(rez, ops.root);

% remove temporary file
delete(fnameTW);
%%
