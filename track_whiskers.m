
%%

c=0;

clear vid_paths vid_names;


load('cnn_8_3_15.mat');
funtype = 'matlab';


gc_file_list();


skipN=20;

%pause(60*60);

% re- did 89 107 90

for pathnum= 100;%[65:109]%68:109 %[100:109];
    vid_path=vid_paths{pathnum};
    vid_name=vid_names{pathnum};
    
    
    result_path=vid_name(1:end-4);
    
    vid = VideoReader(fullfile(vid_path,vid_name));
    Nframes=vid.NumberOfFrames
    
    
    %% make/ init file
    
    mkdir(fullfile(vid_path,result_path));
    ep_file=fullfile(vid_path,result_path,'annotation.mat');
    
    
    load_initialize_epochs_simple; % load or initialize epochs
    
    
    wh_tracking_file=fullfile(vid_path,result_path,'wh_tracking.mat');
    
    whtracking=[];
    whtracking.pathnum=pathnum;
    whtracking.sessionname=epochs.sessionname;
    whtracking.nosedist_display=epochs.nosedist_display;
    %  whtracking.gapdist=epochs.gapdist;
    whtracking.gappos=epochs.gappos;
    % whtracking.retractiondist=epochs.retractiondist;
    %lfps = n_loadlfps(opt,session,mouse,'all',1,'lfp_lowpass_decimate_decimateCheb_1894Hz_ch'); % load low fs version
    
    %% preprocess
    
    
    % first figure out direction mouse is facing, only track half the face
    % (for 2x the speed)
    clf; hold on;
    plot(epochs.nosedist_display(1,:),'k');
    plot(epochs.nosedist_track(2,:),'g');
    f=normpdf([-400:400],0,100);
    f=f./sum(f(:));
    mp=conv(epochs.mousepresent_graded,f,'same')>3;
    
    direction=mp.*0;
    onsets=find(diff(mp)==1);
    for i=1:numel(onsets)-1
        direction(onsets(i):onsets(i+1))=-sign(epochs.nosedist_display(1,onsets(i)));
    end;
    
    
    plot(mp.*350.*direction,'r');
    
    %% set up image ii mapping to stack
    disp('setting up convnet index mapping..');
    I=read(vid,1);
    uim = single(I(:,:,1));
    
    x=0;
    
    isteps=inradius+10:size(uim,1)-inradius-10;
    jsteps = inradius+10:size(uim,2)-inradius-10;
    uim_2_ii=zeros(numel(uim),(((inradius*2)+1).^2));
    for i=isteps
        for j=jsteps
            x=x+1;
            
            ii=sub2ind(size(uim),i+meshgrid(-inradius:inradius)',j+meshgrid(-inradius:inradius));
            uim_2_ii(x,:)= ii(:);
        end;
    end;
    uim_2_ii=uim_2_ii(1:x,:); % now point to tile for each putput/predicted pixel in uim
    stacksize=x;
    
    
    disp('done');
    %% track
    skipn=2;
    
    plotskip=1
    
    skipi=[0:skipn-1];
    
    ifplot=1;
    trackframes=find(mp);
    c=0;  se = strel('ball',3,3);
    se_big = strel('ball',10,10);
    f_big=fspecial('disk', 10);
    %  [0:1000]+92120;%
    % tic;
    lasttic=cputime-10;
    for fnum=16672;%trackframes(1:skipn:end)%1:Nframes;%
        c=c+1;
        nose_x=round(epochs.nosedist_display(1,fnum)+110);
        
        
        I=read(vid,fnum);
        Icrop=I(170:450,10:420,1);
        
        
        
        %nose_y=round(-epochs.nosedist_display(2,fnum)+450);
        if       nose_x>50 & nose_x<400 %& nose_y>150 & nose_y<410
            
            if mod(c,plotskip)==0
                fps=plotskip/(cputime-lasttic);
                fprintf('pathnum %d | %d/%d frames (%d%%) (%f fps) \n',pathnum,c,round(numel(trackframes)/skipn),round(((c*skipn)/numel(trackframes))*100),fps);
                lasttic=cputime;
            end;
            
            I=read(vid,fnum);
            Icrop=I(170:450,10:420,1);
            
            % find nose Y coord
            nose_y_detect = conv2(double(I(166:end,[-15:15]+nose_x+20,1)),f_big,'same')<40;
            plot(mean(nose_y_detect'));
            m=mean(nose_y_detect'); m=m./sum(m);
            epochs.nosedist_display(2,fnum) =min(find(cumsum(m)>.5));
            nose_y=epochs.nosedist_display(2,fnum)+150;
            
            Icrop_nogray=Icrop;
            
            
            widthscale=[1:size(Icrop_nogray,2)];
            
            % Icrop_nogray=imdilate(Icrop_nogray,se);
            
            
            uim = single(I(:,:,1));
            
            % make tiles to feed into CNN
            
            % this is way slow, instead just pre-compute the indices from
            %full image to stack of inradius sized tiles and just slect
            %which ones to use here
            x=0;
            tic
            
            [isteps,jsteps] = meshgrid(inradius+10:size(uim,1)-inradius-10, inradius+10:size(uim,2)-inradius-10);
            
            use_stack = sign(nose_y-isteps(:)+inradius*2-(10*direction(fnum)))~=direction(fnum) & sqrt((nose_x-jsteps(:)+inradius*2).^2+(nose_y-isteps(:)+inradius*2).^2)<110 ;
            
            %{
             use_stack=[];
             for i=isteps
                 for j=jsteps
                     x=x+1;
                     %use_stack(x) = abs(nose_x-j)<150 & abs(nose_y-i)<140 ;
                     use_stack(x) = sign(nose_y-i+inradius*2-(10*direction(fnum)))~=direction(fnum) & sqrt((nose_x-j+inradius*2).^2+(nose_y-i+inradius*2).^2)<110 ;
                     % imstack(:,:,x)=double((uim(i-inradius:i+inradius,j-inradius:j+inradius)./255)-0.5);
                     
                     %  ii=sub2ind(size(uim),i+meshgrid(-inradius:inradius)',j+meshgrid(-inradius:inradius));
                     %  uim_2_ii(x,:)= ii(:);
                 end;
             end;
             
             toc
            %}
            
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
    
    %% save
    save(wh_tracking_file,'whtracking');
    disp(['wh tracking file saved in ',wh_tracking_file]);
    
save(ep_file,'epochs');
save([ep_file,'_video_annotation_snapshot_',date],'epochs','mousepresent');
disp(['epoch file saved in ',ep_file]);

    
end;
