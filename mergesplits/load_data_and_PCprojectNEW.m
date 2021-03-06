if ~exist('loaded', 'var')
    tic 
    if ~isempty(ops.chanMap)
        if ischar(ops.chanMap)
            load(ops.chanMap);
            try
                chanMapConn = chanMap(connected>1e-6);
            catch
                chanMapConn = 1+chanNums(connected>1e-6);
            end
        else
            chanMapConn = ops.chanMap;
        end
    else
        chanMapConn = 1:ops.Nchan;
    end
    batch_path = fullfile(root, 'batches');
    if ~exist(batch_path, 'dir')
        mkdir(batch_path);
    end
    NchanTOT = ops.NchanTOT;
    NT = ops.NT ;
    
    d = dir(fullfile(root, fname));
    ops.sampsToRead = floor(d.bytes/NchanTOT/2);
    
    NTbuff      = NT + 4*ops.ntbuff;
    Nbatch      = ceil(d.bytes/2/NchanTOT /(NT-ops.ntbuff));
    m = memmapfile(fullfile(root, fname),'Format',{'int16',[NchanTOT ops.sampsToRead],'x'});
    DATA = m.DATA.x;
     %% load data into patches, filter, compute covariance, write back to
    % disk
    [b1, a1] = butter(3, ops.fshigh/ops.fs, 'high');
    
    fprintf('Time %3.0fs. Loading raw data... \n', toc);
    Nchan = ops.Nchan;
    CC = gpuArray.zeros( Nchan,  Nchan, 'single');
    if strcmp(ops.whitening, 'noSpikes')
        nPairs = gpuArray.zeros( Nchan,  Nchan, 'single');
    end
    
    for ibatch = 1:Nbatch
        offset = max(0, ((NT - ops.ntbuff) * (ibatch-1) - 2*ops.ntbuff));
        if ibatch==1
            ioffset = 0;
        else
            ioffset = ops.ntbuff;
        end
        inds = offset + [1:NTbuff];
        inds(inds>size(DATA,2)) = size(DATA,2);
        buff = DATA(:, inds);
        
            
        dataRAW = gpuArray(buff);
        dataRAW = dataRAW';
        dataRAW = single(dataRAW);
        dataRAW = dataRAW(:, chanMapConn);

        datr = filter(b1, a1, dataRAW);
        datr = flipud(datr);
        datr = filter(b1, a1, datr);
        datr = flipud(datr);
                
        switch ops.whitening
            case 'noSpikes'
                smin      = my_min(datr, ops.loc_range, [1 2]);
                sd = std(datr, [], 1);
                peaks     = single(datr<smin+1e-3 & bsxfun(@lt, datr, ops.spkTh * sd));
                blankout  = 1+my_min(-peaks, ops.long_range, [1 2]);
                smin      = datr .* blankout;
                CC        = CC + (smin' * smin)/NT;
                nPairs    = nPairs + (blankout'*blankout)/NT;
            otherwise
                CC        = CC + (datr' * datr)/NT;
        end
    end
    %
    CC = CC / ibatch;
    switch ops.whitening
            case 'noSpikes'
                nPairs = nPairs/ibatch;
    end
    fprintf('Time %3.0fs. Channel-whitening filters computed. \n', toc);

    fprintf('Time %3.0fs. Loading raw data and applying filters... \n', toc);
    
    switch ops.whitening
        case 'diag'
            CC = diag(diag(CC));
        case 'noSpikes'
            CC = CC ./nPairs;
    end
    
    [E, D] 	= svd(CC);
    eps 	= 1e-6;
    Wrot 	= E * diag(1./(diag(D) + eps).^.5) * E';
    Wrot    = ops.scaleproc * Wrot;
    %%
    fidW = fopen(fullfile(root, fnameTW), 'w');
   
    i0 = 0;
    wPCA = ops.wPCA(:, 1:3);
    uproj = zeros(5e6,  size(wPCA,2) * Nchan, 'single');
    %
    for ibatch = 1:Nbatch
        offset = max(0, ((NT - ops.ntbuff) * (ibatch-1) - 2*ops.ntbuff));
        if ibatch==1
            ioffset = 0;
        else
            ioffset = ops.ntbuff;
        end
        inds = offset + [1:NTbuff];
        inds(inds>size(DATA,2)) = size(DATA,2);
        buff = DATA(:, inds);
        
        dataRAW = gpuArray(buff);
        dataRAW = dataRAW';
        dataRAW = single(dataRAW);
        dataRAW = dataRAW(:, chanMapConn);
        
        datr = filter(b1, a1, dataRAW);
        datr = flipud(datr);
        datr = filter(b1, a1, datr);
        datr = flipud(datr);
        
        datr = datr(ioffset + (1:NT),:);
        datr    = datr * Wrot;
        
        dataRAW = gpuArray(datr);
        dataRAW = single(dataRAW);
        dataRAW = dataRAW / ops.scaleproc;
        
        % find isolated spikes
        [row, col, mu] = isolated_peaks(dataRAW, ops.loc_range, ops.long_range, ops.spkTh);
        
        % find their PC projections
        uS = get_PCproj(dataRAW, row, col, wPCA, ops.maskMaxChannels);
        
        uS = permute(uS, [2 1 3]);
        uS = reshape(uS,numel(row), Nchan * size(wPCA,2));
        
        if i0+numel(row)>size(uproj,1)
            uproj(1e6 + size(uproj,1), 1) = 0;
        end
        
        uproj(i0 + (1:numel(row)), :) = gather(uS);
        i0 = i0 + numel(row);
        
        datcpu  = gather(int16(datr));
        fwrite(fidW, datcpu, 'int16');
    end
    
    Wrot        = gather(Wrot);
    rez.Wrot    = Wrot;
    
    fclose(fidW);
    fprintf('Time %3.2f. Whitened data written to disk... \n', toc);
    fprintf('Time %3.2f. Preprocessing complete!\n', toc);
    
    loaded = 1;
end





