
%%

% load conv net coefficients
% alternatively, use train_cnn.m to train the convnet from scratch
addpath('ConvNet-master\');

load(fullfile('example_data','cnn_8_3_15.mat'));
funtype = 'matlab';

vid = VideoReader(fullfile('example_data/example_video.avi'));
Nframes=vid.NumberOfFrames
    
    
    %% make/ init file

    whtracking=[];
    whtracking.nosedist_display=epochs.nosedist_track;

    %% set up image ii mapping to stack
    disp('setting up convnet index mapping..');
    I=read(vid,1);
    uim = single(I(:,:,1));
    
    x=0;
    
    isteps=inradius+10:size(uim,1)-inradius-10;  %steps for tiling the image
    jsteps = inradius+10:size(uim,2)-inradius-10;
    
    uim_2_ii=zeros(numel(uim),(((inradius*2)+1).^2)); 
    % this is the mapping from linear input image pixel index to list of 
    % (inradius*2)+1) X (inradius*2)+1) indices that make up the tile to go
    % with that (output) pixel. Once we have this mapping, we can just feed
    % input_image(uim_2_ii(linear desired output pixel index,:)) into the CNN
    % which is vastly faster than getting the -inradius:inradius X
    % -inradius:inradius tile each time.
    
    for i=isteps
        for j=jsteps
            x=x+1;
            ii=sub2ind(size(uim),i+meshgrid(-inradius:inradius)',j+meshgrid(-inradius:inradius)); %linear indices for that tile
            uim_2_ii(x,:)= ii(:);
        end;
    end;
    uim_2_ii=uim_2_ii(1:x,:); % now point to tile for each putput/predicted pixel in uim
    stacksize=x;
    
    disp('done');
    %% track
    skipn=1; % skip every Nth frame?
    
    plotskip=1
    
    skipi=[0:skipn-1];
    
    ifplot=1;
    trackframes=1:Nframes; 
    % we'd restrict tracking to only an interesting subset 
    % of frames here (i.e. mous epresent in the right distance to the 
    % target to be interesting etc.)
    
    c=0;  se = strel('ball',3,3);
    se_big = strel('ball',10,10);
    f_big=fspecial('disk', 10);
    %  [0:1000]+92120;%
    % tic;
    lasttic=cputime-10;
    for fnum=trackframes
        c=c+1;
        nose_x=round(epochs.nosedist_track(1,fnum)+110);
        
        
        I=read(vid,fnum);
        Icrop=I(170:450,10:420,1);
        
        
        
        %nose_y=round(-epochs.nosedist_display(2,fnum)+450);
        if       nose_x>50 & nose_x<400 %& nose_y>150 & nose_y<410
            
            if mod(c,plotskip)==0
                fps=plotskip/(cputime-lasttic);
                fprintf('%d/%d frames (%d%%) (%f fps) \n',c,round(numel(trackframes)/skipn),round(((c*skipn)/numel(trackframes))*100),fps);
                lasttic=cputime;
            end;
            
            I=read(vid,fnum);
            Icrop=I(170:450,10:420,1);
            
            % find nose Y coord
            nose_y_detect = conv2(double(I(166:end,[-15:15]+nose_x+20,1)),f_big,'same')<40;
            plot(mean(nose_y_detect'));
            m=mean(nose_y_detect'); m=m./sum(m);
            epochs.nosedist_display(2,fnum) =min(find(cumsum(m)>.5));
            nose_y=epochs.nosedist_display(2,fnum);
            
            Icrop_nogray=Icrop;
            widthscale=[1:size(Icrop_nogray,2)];
       
            uim = single(I(:,:,1));
            
            % make tiles to feed into CNN
            % use pre-computed tile indices 
            %  and just slect
            %which ones to use here
            x=0;
            tic
            
            [isteps,jsteps] = meshgrid(inradius+10:size(uim,1)-inradius-10, inradius+10:size(uim,2)-inradius-10);
            
            use_stack =  sqrt((nose_x-jsteps(:)+inradius*2).^2+(nose_y-isteps(:)+inradius*2).^2)<110 ;
            
            
            pred=ones(stacksize,2);
            runon=find(use_stack);
            %pred(runon,:) = cnnclassify(layers, weights, params,
            %imstack(:,:,runon), funtype); % way slow
            
            ii=uim_2_ii(runon,:);
            imstack_fast = ((reshape( uim(ii'), 11,11,numel(runon))./255)-0.5);
            pred(runon,:) = cnnclassify(layers, weights, params, imstack_fast, funtype);
            
            isteps_lin=inradius+10:size(uim,1)-inradius-10; %just as output size computation
            jsteps_lin = inradius+10:size(uim,2)-inradius-10;
            iout=flipud(rot90(reshape(pred(:,2)',numel(jsteps_lin),numel(isteps_lin))));
            
            
            %  rem_mouse=imerode(uim(inradius+10:end-inradius-10,inradius+10:end-inradius-10),se_big)>10;
            %fatser
            rem_mouse = (conv2(double(uim(inradius+10:end-inradius-10,inradius+10:end-inradius-10)<100),f_big,'same')<.2);
            
            % identify rough whisker angle via hough transform
            
            Imask=iout.*0;
            try
                %j=round(epochs.nosedist_display(1,fnum)+110);
                %i=round(-epochs.nosedist_display(2,fnum)+450);
                j=nose_x;
                i=nose_y;
                
                Imask(i, j)=Imask(i, j)+1;
            end;
            if sum(Imask(:))>0
                f=fspecial('disk',100); f=f./sum(f(:));
                Imask=conv2(Imask,f,'same');
                Imask=Imask./max(Imask(:));
            end;
            
            Ihough = ((Imask.*(1-iout))>0.2).*rem_mouse;
            
            if ifplot & mod(c,plotskip)==0
                clf;
                hold on;
                imagesc((uim(isteps_lin,jsteps_lin)./1000)+(1-iout)+Imask./10); colormap(gray); daspect([1 1 1]);
                plot([1 1].* epochs.gappos+110,[0 400],'g');
                plot(nose_x, nose_y,'ro');
                drawnow;
            end;
            
            [H,theta,rho] = hough(Ihough);
            P = houghpeaks(H,20,'threshold',ceil(0.01*max(H(:))));
            lines = houghlines(Ihough,theta,rho,P,'FillGap',4,'MinLength',6);
            
            %   clf;
            %   imagesc(Ihough); colormap(gray); daspect([1 1 1]);
            %   hold on;
            if ifplot & mod(c,plotskip)==0
                for k = 1:length(lines)
                    xy = [lines(k).point1; lines(k).point2];
                    plot(xy(:,1),xy(:,2),'LineWidth',2,'Color','green');
                end
                drawnow;
            end;
            
            whtracking.intersect_mean(fnum) = mean(mean(Ihough(:, round(epochs.gappos)+[100:120])));
            whtracking.intersect_im=Ihough(:, round(epochs.gappos)+[100:120]);
            whtracking.lines{fnum}=lines;
            
            %   fprintf(' %f sec \n',frametime)
            
        end;
        %{
    gridcount=6;
    clear pos imstack;
    isteps=ceil(linspace(1,size(iout,1)-1,gridcount));
    jsteps=ceil(linspace(1,size(iout,2)-1,gridcount));
    for i=1:gridcount-1
        for j=1:gridcount-1
            
        
            Ihough=1-iout;
            Ihough=Ihough(isteps(i):isteps(i+1),jsteps(j):jsteps(j+1))>.2;
            
            [H,theta,rho] = hough(Ihough);
            P = houghpeaks(H,6,'threshold',ceil(0.1*max(H(:))));
            lines = houghlines(Ihough,theta,rho,P,'FillGap',5,'MinLength',7);
            
            clf;
            imagesc(Ihough); colormap(gray); daspect([1 1 1]);
            hold on;
            
            for k = 1:length(lines)
                xy = [lines(k).point1; lines(k).point2];
                plot(xy(:,1),xy(:,2),'LineWidth',2,'Color','green');
            end
            drawnow;
            pause(1);
            
            
        end;
    end;
   
        %}
        
        
    end;
    
