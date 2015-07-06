%% this file is used to tune the mpc solver.

clear
close all
rbt.x = 10;
rbt.y = 10;
rbt.speed = 3;
peak = {[20;30],[30;10]};
hor = 5;
field.x = 50;
field.y = 50;

mu = [30;25];
sig = [30,0;0,30];
[px,py] = meshgrid(1:field.x,1:field.y);
map = (reshape(mvnpdf([px(:),py(:)],mu',sig),field.x,field.y))';
    
for ii = 1:100
    x = sdpvar(2,hor+1);
    u = sdpvar(1,hor);
    
    % find initial solution
    %{
    init_x = zeros(size(x));
    init_u = zeros(size(u));
    init_x(:,1) = [rbt.x;rbt.y];
    for kk = 1:hor
        ang = calAngle(mu-init_x(:,kk));
        init_u(kk) = ang;
        init_x(:,kk+1) = init_x(:,kk)+rbt.speed*[cos(init_u(kk));sin(init_u(kk))];
    end
    assign(x,init_x);
    assign(u,init_u); 
    %}
    
    % obj1
    %{
    if rem(ii,2) == 0
        obj = sum((x(1:2,2)-peak{2}).^2);
    elseif rem(ii,2) == 1
        obj = sum((x(1:2,2)-peak{1}).^2);
    end
    %}
    
    % obj2
    
    obj = 0;
    for jj = 1:hor
        obj = obj+ 1 - mvnpdf(x(:,jj+1),mu,sig);
    end
    constr = [x(:,1) == [rbt.x;rbt.y]];
    for jj = 1:hor
        constr = [constr,x(:,jj+1) == x(:,jj)+rbt.speed*[cos(u(jj));sin(u(jj))]];
        constr = [constr,x(:,jj+1) >= [1;1] , x(:,jj+1) <= [field.x;field.y]];
        constr = [constr,-2*pi<= u(jj) <= 2*pi];
    end
    
       
    optset = sdpsettings('solver','fmincon','usex0',1,'debug',1,'verbose',1,...
        'fmincon.Algorithm','interior-point','fmincon.Display','iter-detailed','fmincon.Diagnostics','on',...
        'fmincon.TolCon',1e-5,'fmincon.TolFun',1e-5);
    sol = optimize(constr,obj,optset);
    if sol.problem == 0
        opt_x = value(x);
        opt_u = value(u);
    else
        error(sprintf('fail to solve mpc'))
    end
    
    % predict one-step robot motion and send it to
    %         pre_x = opt_x(1:2,end)+u(1,end)*[cos(u(2,end));sin(u(2,end))];
    rbt.x = opt_x(1,2);
    rbt.y = opt_x(2,2);
    rbt.opt_x{ii} = opt_x;
    rbt.opt_u{ii} = opt_u;
    figure(1)
    contourf(map')
    hold on
    plot (rbt.x,rbt.y,'rd','MarkerSize',8,'LineWidth',3)
    grid on
    xlim([1,field.x])
    ylim([1,field.y])    
end