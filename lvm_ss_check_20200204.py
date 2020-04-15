#!/usr/bin/velocity-python3.5

import sys
try:
  import subprocess
except ImportError:
  sys.exit(0)

G_DEBUG=False
G_STATUS = 0
G_LEVEL = 1
G_IND_STR = "start "
G_IN_CRITICAL = 60
G_IN_WARNING = 40

G_PROCESSED = []

## The true values will be passed from check_mk ##
G_WARNING = 45
G_CRITICAL = 60


def FN_VALUE_CHECK(in_value = 1.0):
    ## check to see if value is outside of the warning or critical values ##

    if  G_STATUS < 2 :
        if in_value >= G_IN_CRITICAL :
            G_STATUS = 2

        if in_value >= G_IN_WARNING  and in_value < G_IN_CRITICAL :
            G_STATUS=1

        ### End of FN_VALUE_CHECK ##

def FN_DEBUG(argv=""):
    ## if G_DEBUG=True then print out the text ##
    if G_DEBUG == True:
        print(argv)
    ### End of FN_DEBUG ###


def FN_VG_get():
    ## return a list of VGs ##
    stdout,stderr = subprocess.Popen(['/usr/sbin/vgs', '--noheading','-o', 'vg_name' ], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()
    
    vgs = stdout.decode("utf-8").strip().replace("\t", "").replace(" ", "")
    vgs = vgs.split('\n')
    return vgs
    ### End of FN_VG_get ###


def FN_LV_header():
    l_lv_header = ('lv_name','lv_size','data_percent','metadata_percent','snap_percent','lv_when_full','time','lv_descendants','origin','lv_attr')
    print( l_lv_header )
    ### End of FN_LV_header ###    


def FN_LV_get( arg1 = 'dbP001'):
    stdout,stderr = subprocess.Popen(['/usr/sbin/lvs', arg1, '--noheading','-o',\
    'lv_name,lv_size,data_percent,metadata_percent,snap_percent,lv_when_full,time,lv_descendants,origin,lv_attr', \
    '--separator', '|', '-O', 'lv_name', '-S', 'lv_attr=~[^Vwi]'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()
    
    lvs = stdout.decode("utf-8").strip().replace("\t", "").replace(" ", "")
    lvs = lvs.split('\n')
    
    mylisttuple = [tuple(map(str, i.split('|'))) for i in lvs]
    ## print( mylisttuple )
    return  mylisttuple 
    ### End of FN_LV_get ###


def  FN_LV_snap_tree (arg_gv, arg_lv, arg_t_lvl):
    ## walk the snapshot tree to reach the leaf nodes ##

    ## check if the arg_lv has already been processed
    if arg_lv not in G_PROCESSED:
        arg_t_lvl += 1
        FN_DEBUG('lv not in G_PROCESSED')
        G_PROCESSED.append(arg_lv)
        #print( "I'm here with arg_lv="+arg_lv)
        #print(G_LV_LIST_TUPLE)
        ###        i=0
        ###        for mytuple in G_LV_LIST_TUPLE:
        ###            print( "index="+str(i)+ " type="+str(mytuple[0]) )
        ###            i += 1
        ###            if mytuple[0] == arg_lv:
        ###                L_LIST_IND = i
        ###
        L_LIST_IND = [i for i, tupl in enumerate(G_LV_LIST_TUPLE) if tupl[0] == arg_lv]
        FN_DEBUG( "index=" + str(L_LIST_IND[0]) )
        ## print out the tuple
        #print( "test list_tuple[" + str(L_LIST_IND) + "]=" + str(G_LV_LIST_TUPLE[ L_LIST_IND ] ) ) 
        FN_DEBUG( "FN_LV_snap_tree: list_tuple[" + str(L_LIST_IND[0]) + "]=" + str(G_LV_LIST_TUPLE[ L_LIST_IND[0] ] ) ) 

        (lv_name,lv_size,data_percent,metadata_percent,snap_percent,lv_when_full,time,lv_descendants,origin,lv_attr)=G_LV_LIST_TUPLE[L_LIST_IND[0]]
        for ind in range(arg_t_lvl):
            print("    ",  end=' ')

        ## template: lvtechst_D003_20200124_1014    size=20.00g data=39.96% snap=39.96% meta=0% action_when_full=>< timesstamp=2020-01-2410:16:12+0000 G_STATUS=2

        print("%-10s"% lv_name  )
        ## check the PCT values to see if they breach the G_WARNING or G_CRITICAL thresholds
        if lv_descendants != "" :
            ## increase the indentation
            #G_LEVEL += 1
            #G_IND_STR = G_IND_STR + "    "
            FN_DEBUG( "FN_LV_snap_tree: lv_descendants = " + lv_descendants )
            L_DESC_LIST=lv_descendants.split(",")
            FN_DEBUG( "L_DESC_LIST="+str(L_DESC_LIST) )
            for lv_branch in L_DESC_LIST :
                 FN_DEBUG( "FN_LV_snap_tree: processing " + str(lv_branch ) )
                 FN_LV_snap_tree ( arg_gv, lv_branch, arg_t_lvl )
            ## decrease indentation
        FN_DEBUG("- - - - - - - - - - ")


    ### End of FN_LV_snap_tree ###


###def FN_MAIN() :
for vg in FN_VG_get():
    G_LEVEL = 0
    G_PROCESSED = []
    #print("\n\t\tprocessing vg "+ str(vg))

    #print( "\n\n- - - - - - - - - - - - - " )

    G_LV_LIST_TUPLE=FN_LV_get(vg)

    #print( G_LV_LIST_TUPLE )
    #print( "- - - - - - - - - - - - - \n\n" )

    ## iterate through all LVs ##
    for L_LIST_IND, l_tuple in enumerate(G_LV_LIST_TUPLE) :
        (lv_name,lv_size,data_percent,metadata_percent,snap_percent,lv_when_full,time,lv_descendants,origin,lv_attr)=G_LV_LIST_TUPLE[L_LIST_IND]
        #print( "FN_LV_snap_tree( "+ vg +", "+ lv_name +")" )
        FN_LV_snap_tree( vg, lv_name, G_LEVEL )
    ### End of FN_MAIN ###


#FN_LV_header()
print( "" )

##FN_MAIN()
exit()

## for testing ##
#G_LV_LIST_TUPLE=FN_LV_get('gpP001')
##print(G_LV_LIST_TUPLE)
#FN_LV_snap_tree( 'gpP001', 'lvdata01')

#G_LV_LIST_TUPLE=FN_LV_get('dbP001')
##print(G_LV_LIST_TUPLE)
#FN_LV_snap_tree( 'dbP001', 'lvdata03')

#for mytuple in G_LV_LIST_TUPLE:
#  print( mytuple[0] )
